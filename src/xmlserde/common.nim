## Common routines for this project.

import std/[parsexml, strformat, macros, times]

template xmlName*(name: string) {.pragma.}
    ## Annotates a field of an object.
    ##
    ## `xmlName` takes a string as argument. When specified, the string
    ## argument becomes the node name that the field is serialized to or
    ## deserialized from. The use case is for XML nodes that have a
    ## Nim-identifier-incompatible name.
template xmlFlatten* {.pragma.}
    ## Annotates a field of an object. Type of field must be an object (It
    ## doesn't make sense otherwise).
    ##
    ## Replaces the annotated field with the field type's fields. The use case
    ## is for splitting up a node that has a lot of fields, so that the
    ## memory representation is easier to work with. Another use case is for
    ## the `xsd:extension` XSD node for types that extend another type.
template xmlAttr* {.pragma.}
    ## Annotates a field of an object. Type of field must be primitive.
    ##
    ## The annotated field is serialized as an attribute of the contained
    ## object, or deserialized from an attribute of the contained object.
template xmlText* {.pragma.}
    ## Annotates a field of an object. Type of field must be primitive.
    ##
    ## The annotated field will not appear as an XML "element", but rather as
    ## the "text/chardata" field of the contained object. This decorator only
    ## makes sense if there are no other fields in the object, or there are
    ## only attributes.
    ##
    ## The use case is when the contained object is meant to be a simple
    ## primitive type, except it has attributes.

template xmlNameOf*(field: typed, def: string): string =
    ## Convenience for getting `xmlName` pragma with a default. `field` is a
    ## "field" from `fieldPairs`.
    bind hasCustomPragma
    bind getCustomPragmaVal
    when hasCustomPragma(field, xmlName):
        getCustomPragmaVal(field, xmlName)
    else:
        def

type
    Primitive* = SomeInteger | SomeFloat | string | bool | enum | DateTime | Time
        ## Supported primitive types for all marshalling.

func errorMsgX*(inp: XmlParser, msg: string): string =
    let extraMsg = if inp.kind == xmlError: inp.errorMsg else: ""
    inp.errorMsg(msg & extraMsg)

func expectKind*(inp: XmlParser, kind: set[XmlEventKind]) =
    if inp.kind notin kind:
        raise newException(Exception,
            inp.errorMsgX(&"Expected XML kind to be of {$kind}, but got {$inp.kind}"))
func expectKind*(inp: XmlParser, kind: XmlEventKind) = inp.expectKind {kind}

