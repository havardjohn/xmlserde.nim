## This implements a very simple marshalling algorithm between XML and Nim
## structures. All marshalling routines are exported from this module. See
## `xmlserde/ser <xmlserde/ser.html>`_ for the serialization routines and
## `xmlserde/deser <xmlserde/deser.html>`_ for the deserialization routines.
## Simple wrappers are implemented in this module.
##
## .. note:: This does not support variant objects as of writing. It is \
## planned for the future.
##
## # Pragma attributes
##
## There are various pragmas available that can be attached to fields of
## objects to alter the serialization and deserialization of the field. Please
## see `xmlserde/common <xmlserde/common.html>`_ for documentation on those.
## All these attributes are exported from this module.
##
## # Compiler flags
##
## Use `-d:xmlSerdeParseXmlDebug` for debugging how the `XmlParser` steps
## during deserialization.

# NOTE: For the implementation of marshalling variant objects: The
# discriminator shall not be serialized, deserialized by design. This decision
# is based on being convenient with XSD schemas. For XSD schemas, the
# `xsd:choice` node describes a list of elements that are mutually exclusive,
# but the discriminator itself is not present.

import std/[streams, parsexml, strutils]
import results
import xmlserde/[ser, deser, common]

export ser, deser, xmlName, xmlFlatten, xmlAttr, xmlText

type
    DeserializeResult[T] = Result[T, string]

proc skipUntilElem(inp: var XmlParser, name: string) =
    ## Skips nodes until a node on the same depth with the given name is found
    inp.expectKind {xmlElementStart, xmlElementOpen}
    while inp.kind != xmlEof:
        if inp.kind in {xmlElementStart, xmlElementOpen} and inp.elementName == name:
            return
        inp.next

proc deser*[T](content: Stream, rootName, fileName = ""): DeserializeResult[T] =
    ## Simple deserialization of an XML stream into `T`.
    ##
    ## `rootName` can be specified, in which case `rootName` will be the node
    ## where deserialization begins. The name of the root node is discarded,
    ## but all attributes of the root is deserialized if possible.
    ##
    ## `fileName` is the name of the file if applicable. This string is only
    ## used for error messages.
    var x: XmlParser
    x.open(content, fileName)
    try:
        x.next # Skip from xmlError (start) into first node
        if rootName != "":
            x.skipUntilElem(rootName)
            x.next
        var ret: T
        let msgs = x.deser(ret)
        if msgs.len > 0:
            result = err(msgs.join("\n"))
        else:
            result = ok(ret)
    finally:
        x.close

proc deserString*[T](content: string, rootName, fileName = ""): DeserializeResult[T] =
    ## Convenience wrapper around `deser`.
    # NOTE: The name cannot be `deser` as it conflicts with the `deser` proc
    # for primitive types.
    deser[T](newStringStream(content), rootName, fileName)

proc deserFile*[T](fileName: string, rootName = ""): DeserializeResult[T] =
    deser[T](openFileStream(fileName), rootName, fileName)
