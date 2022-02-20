## Deserialization implementation.

import std/[strutils, macros, strtabs, options, logging, strformat]
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

func elemName(inp: XmlParser): string =
    ## A wrapper of `XmlParser.elementName` that captures the string at the
    ## current state of the parser, without the possibility of the string being
    ## mutated by `XmlParser.next()`. This is needed because Nim `string`s are
    ## not COW.
    result.deepCopy(inp.elementName)

proc errorMsgFailDeser(inp: XmlParser, typ: typedesc) =
    logging.warn inp.errorMsgX &"Current node couldn't be deserialized into object {$typ}"

func deser[T: SomeSignedInt](inp: string, outp: var T) = outp = inp.parseBiggestInt.T
func deser[T: SomeUnsignedInt](inp: string, outp: var T) = outp = inp.parseBiggestUInt.T
func deser(inp: string, outp: var SomeFloat) = outp = inp.parseFloat
func deser(inp: string, outp: var string) = outp = inp
func deser(inp: string, outp: var bool) = outp = inp.parseBool
func deser[T: enum](inp: string, outp: var T) = outp = parseEnum[T](inp)

proc deser*[T: Primitive](inp: var XmlParser, outp: var T) =
    case inp.kind
    of xmlCharData: inp.charData.deser(outp)
    of xmlAttribute: inp.attrValue.deser(outp)
    else: inp.expectKind {xmlCharData, xmlAttribute}
    inp.next

proc deser*[T: object](inp: var XmlParser, outp: var T)

proc deser*[T](inp: var XmlParser, outp: var seq[T]) =
    ## Deserialize by appending deserialized type to end of sequence.
    outp.add(default T)
    inp.deser(outp[^1])

proc deser*[T](inp: var XmlParser, outp: var Option[T]) =
    outp = some(default T)
    inp.deser(outp.get)

proc deserField[T: object](inp: var XmlParser, xmlName: string, outp: var T) =
    template deserFieldInner[T: object](outp: var T) =
        for key, val in fieldPairs outp:
            when hasCustomPragma(val, xmlFlatten):
                deserFieldInner(val)
            else:
                if xmlName =?= xmlNameOf(val, key):
                    inp.deser(val)
                    return
        inp.errorMsgFailDeser(T.type)
    deserFieldInner(outp)

proc deserAttrs[T: object](inp: var XmlParser, outp: var T) =
    while inp.kind == xmlAttribute:
        inp.deserField(inp.attrKey, outp)
        inp.next
    if inp.kind == xmlElementClose:
        inp.next

proc deserText[T: object](inp: var XmlParser, outp: var T) =
    for key, val in fieldPairs outp:
        when hasCustomPragma(val, xmlText):
            inp.deser(val)
            return
    inp.errorMsgFailDeser(T.type)

proc deser*[T: object](inp: var XmlParser, outp: var T) =
    inp.deserAttrs(outp)
    if inp.kind == xmlCharData:
        inp.deserText(outp)
        return
    while inp.kind notin {xmlElementEnd, xmlEof}:
        let elemName = inp.elemName
        inp.next
        inp.deserField(elemName, outp)
        inp.next
