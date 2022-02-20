## Serialization implementation.

import std/[macros, xmltree, typetraits, sequtils, strtabs, options]
import common

func subnodes(node: XmlNode): seq[XmlNode] =
    result = newSeq[XmlNode](node.len)
    for i in 0..<node.len:
        result[i] = node[i]

func ser*[T: Primitive](inp: T): XmlNode =
    newText($inp)

func formatObjectSer(node: XmlNode, name: string): XmlNode =
    if node.kind == xnElement:
        node.tag = name
        node
    else:
        name.newXmlTree([node])

func ser*[T: object | tuple](inp: T): XmlNode =
    var
        attrs = newStringTable()
        subs = newSeq[XmlNode]()
    for key, val in inp.fieldPairs:
        const xmlName = xmlNameOf(val, key)
        when hasCustomPragma(val, xmlFlatten):
            subs &= val.ser.subnodes
        elif hasCustomPragma(val, xmlAttr):
            bind stripGenericParams
            when stripGenericParams(val.type) is Option:
                if val.isSome: attrs[xmlName] = $val.get
            else:
                attrs[xmlName] = $val
        elif hasCustomPragma(val, xmlText):
            doAssert val.type is Primitive
            subs.add newText($val)
        else:
            bind stripGenericParams
            when stripGenericParams(val.type) is Option:
                if val.isSome: subs.add val.get.ser.formatObjectSer(xmlName)
            elif stripGenericParams(val.type) is seq:
                subs &= val.mapIt(it.ser.formatObjectSer(xmlName))
            else:
                subs.add val.ser.formatObjectSer(xmlName)
    "".newXmlTree(subs, attrs)
