## Deserialization implementation.

import std/[strutils, macros, strtabs, options, logging, strformat, times, parseutils]
import common

# Easier debugging for tests
when defined xmlSerdeParseXmlDebug:
    import std/parsexml except next
    proc next(inp: var XmlParser) =
        parsexml.next(inp)
        echo &"next: {$inp.kind}"
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

proc parseTime(s: string, outp: var Time): bool =
    try:
        outp = s.parseTime("HH:mm:sszzz", local())
        true
    except TimeParseError:
        false

proc parseDateTime(s: string, outp: var DateTime): bool =
    try:
        outp = s.parse("yyyy-MM-dd'T'HH:mm:sszzz")
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
proc deser(inp: string, outp: var Time): bool = inp.parseTime(outp)

proc deser*[T: Primitive](inp: var XmlParser, outp: var T): seq[string] =
    let str =
        case inp.kind
        of xmlCharData: inp.charData
        of xmlAttribute: inp.attrValue
        else: inp.expectKind {xmlCharData, xmlAttribute}; ""
    if not str.deser(outp):
        result = @[inp.errorMsgX("Failed to parse primitive")]
    inp.next

proc deser*[T: object](inp: var XmlParser, outp: var T): seq[string]

proc deser*[T](inp: var XmlParser, outp: var seq[T]): seq[string] =
    ## Deserialize by appending deserialized type to end of sequence.
    outp.add(default T)
    inp.deser(outp[^1])

proc deser*[T](inp: var XmlParser, outp: var Option[T]): seq[string] =
    outp = some(default T)
    inp.deser(outp.get)

proc deserField[T: object](inp: var XmlParser, xmlName: string, outp: var T): seq[string] =
    template deserFieldInner[T: object](outp: var T) =
        for key, val in fieldPairs outp:
            when hasCustomPragma(val, xmlFlatten):
                deserFieldInner(val)
            else:
                if xmlName =?= xmlNameOf(val, key):
                    return inp.deser(val)
    deserFieldInner(outp)

proc deserAttrs[T: object](inp: var XmlParser, outp: var T): seq[string] =
    while inp.kind == xmlAttribute:
        result &= inp.deserField(inp.attrKey, outp)
        inp.next
    if inp.kind == xmlElementClose:
        inp.next

proc deserText[T: object](inp: var XmlParser, outp: var T): seq[string] =
    for key, val in fieldPairs outp:
        when hasCustomPragma(val, xmlText):
            return inp.deser(val)

proc deser*[T: object](inp: var XmlParser, outp: var T): seq[string] =
    result = inp.deserAttrs(outp)
    if inp.kind == xmlCharData:
        result &= inp.deserText(outp)
        return
    while inp.kind notin {xmlElementEnd, xmlEof}:
        let elemName = inp.elemName
        inp.next
        result &= inp.deserField(elemName, outp)
        inp.next
