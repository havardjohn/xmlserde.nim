## Deserialization implementation.

import std/[
    macros,
    options,
    parseutils,
    strformat,
    strtabs,
    strutils,
    times,
    typetraits,
]
import common

# Easier debugging for tests
when defined xmlDeserDebug:
    import std/parsexml except next
    template next(inp: var XmlParser) =
        parsexml.next(inp)
        let val =
            case inp.kind
            of xmlCharData, xmlWhitespace: parsexml.charData(inp)
            of xmlAttribute: "$# = \"$#\"" % [parsexml.attrKey(inp), parsexml.attrValue(inp)]
            else: ""
        let info = instantiationInfo(-1, true)
        echo "$#($#, $#) Hint: Next $# with val \"$#\" for `XmlParser.next`" % [
            $info.filename,
            $info.line,
            $info.column,
            $inp.kind,
            val
        ]
else:
    import std/parsexml

func `=?=`(x, y: string): bool = cmpIgnoreCase(x, y) == 0

func parseBool(s: string, outp: var bool): bool =
    let lower = s.toLowerAscii
    case lower
    of "y", "yes", "true", "1", "on":
        outp = true
        true
    of "n", "no", "false", "0", "off":
        outp = false
        true
    else:
        false

func parseEnum[T: enum](s: string, outp: var T): bool =
    try:
        outp = parseEnum[T](s)
        true
    except ValueError:
        false

proc parseDateTime(s: string, outp: var DateTime): bool =
    try:
        outp = s.parse("yyyy-MM-dd'T'HH:mm:sszzz") # ISO8601
        true
    except TimeParseError:
        false

func elemName(inp: XmlParser): string =
    ## A wrapper of `XmlParser.elementName` that captures the string at the
    ## current state of the parser, without the possibility of the string being
    ## mutated by `XmlParser.next()`. This is needed because Nim `string`s are
    ## not COW.
    result.deepCopy(inp.elementName)

template parseBiggestTempl(typ: typedesc, parser): bool {.dirty.} =
    var big: typ
    if inp.parser(big) == 0:
        return false
    if big > T.high or big < T.low:
        false
    else:
        outp = big.T
        true

func deser[T: SomeSignedInt](inp: string, outp: var T): bool =
    parseBiggestTempl(BiggestInt, parseBiggestInt)
func deser[T: SomeUnsignedInt](inp: string, outp: var T): bool =
    parseBiggestTempl(BiggestUInt, parseBiggestUInt)
func deser(inp: string, outp: var SomeFloat): bool =
    parseBiggestTempl(BiggestFloat, parseBiggestFloat)
func deser(inp: string, outp: var string): bool = outp = inp; true
func deser(inp: string, outp: var bool): bool = inp.parseBool(outp)
func deser[T: enum](inp: string, outp: var T): bool = parseEnum[T](inp, outp)
proc deser(inp: string, outp: var DateTime): bool = inp.parseDateTime(outp)

proc deser*[T: Primitive](inp: var XmlParser, outp: var T): seq[string] =
    let str =
        case inp.kind
        of xmlCharData:
            var str: string
            while true:
                str &= inp.charData
                inp.next
                if inp.kind notin {xmlCharData, xmlWhitespace}: break
            str
        of xmlAttribute: inp.attrValue
        else: inp.expectKind {xmlCharData, xmlAttribute}; ""
    if not str.deser(outp):
        result = @[inp.errorMsgX(&"Failed to parse primitive \"{str}\"")]

proc deser*[T: object and not DateTime](inp: var XmlParser, outp: var T): seq[string]

proc deser*[T](inp: var XmlParser, outp: var seq[T]): seq[string] =
    ## Deserialize by appending deserialized type to end of sequence.
    outp.add(default T)
    inp.deser(outp[^1])

proc deser*[T](inp: var XmlParser, outp: var Option[T]): seq[string] =
    outp = some(default T)
    inp.deser(outp.get)

proc skipNode(inp: var XmlParser) =
    var lvl = 1
    while true:
        inp.next
        case inp.kind
        of {xmlElementStart, xmlElementOpen}:
            inc lvl
        of xmlElementEnd:
            dec lvl
            if lvl == 0:
                return
        else: discard

proc deserField[T](inp: var XmlParser, xmlName: string, outp: var T,
                           isAttr: static bool): seq[string] =
    template deserFieldInner[T](outp: var T) {.dirty.} =
        for key, val in fieldPairs outp:
            when hasCustomPragma(val, xmlFlatten):
                deserFieldInner(val)
            else:
                if xmlName =?= xmlNameOf(val, key):
                    return inp.deser(val)
    deserFieldInner(outp)
    # Handle field not existing in object fields:
    when isAttr:
        inp.expectKind xmlAttribute
        inp.next # Skips ignored xmlAttribute
    else:
        inp.expectKind {xmlCharData, xmlAttribute, xmlElementStart, xmlElementOpen}
        inp.skipNode

proc deserAttrs[T](inp: var XmlParser, outp: var T,
                   doneFields: var seq[string]): seq[string] =
    if inp.kind != xmlAttribute:
        return
    while true:
        doneFields &= inp.attrKey
        result &= inp.deserField(inp.attrKey, outp, true)
        inp.next
        if inp.kind != xmlAttribute: break
    inp.expectKind xmlElementClose
    inp.next

proc deserText[T](inp: var XmlParser, outp: var T,
                  doneFields: var seq[string]): seq[string] =
    for key, val in fieldPairs outp:
        when hasCustomPragma(val, xmlText):
            doneFields &= key
            return inp.deser(val)

proc deser*[T: object and not DateTime](inp: var XmlParser, outp: var T): seq[string] =
    var doneFields: seq[string]
    result = inp.deserAttrs(outp, doneFields)
    if inp.kind == xmlCharData:
        result &= inp.deserText(outp, doneFields)
        return
    while inp.kind notin {xmlElementEnd, xmlEof}:
        inp.expectKind {xmlElementStart, xmlElementOpen}
        let elemName = inp.elemName
        doneFields &= elemName
        inp.next
        result &= inp.deserField(elemName, outp, false)
        inp.expectKind xmlElementEnd
        inp.next
    bind stripGenericParams
    for key, val in fieldPairs outp:
        when not (stripGenericParams(val.type) is seq or
                  stripGenericParams(val.type) is Option):
            if not doneFields.anyIt(it =?= xmlNameOf(val, key)):
                result &= inp.errorMsgX("Field `$#.$#` was not deserialized" % [$T, key])
