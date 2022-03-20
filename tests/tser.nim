import std/[xmltree, unittest, options, times]
import xmlserde

func `==`(x, y: XmlNode): bool = $x == $y

suite "serialization":
    test "Basic":
        type
            TestObj = object
                a: int
        let obj = TestObj(a: 3)
        check obj.ser == "".newXmlTree([<>a(newText"3")])

    test "Nested":
        type
            NestedObj = object
                x, y: int
            TestObj = object
                a, b: NestedObj
                c: int
        let obj = TestObj(a: NestedObj(x: 1, y: 3), b: NestedObj(x: 2, y: 4), c: 5)
        check obj.ser == "".newXmlTree([
            <>a(
                <>x(newText"1"),
                <>y(newText"3")),
            <>b(
                <>x(newText"2"),
                <>y(newText"4")),
            <>c(newText"5")])

    test "Attributes":
        type
            TestObj = object
                x {.xmlAttr.}: string
                inner {.xmlText.}: int
        let obj = TestObj(x: "Helloo", inner: 42)
        check obj.ser == "".newXmlTree([newText"42"], {"x": "Helloo"}.toXmlAttributes)

    test "Attributes on complex objects":
        type
            InnerObj = object
                x: int
            TestObj = object
                attr {.xmlAttr.}: string
                y: int
                z: InnerObj
        let obj = TestObj(attr: "Yup", y: 12, z: InnerObj(x: 3))
        check obj.ser == "".newXmlTree([
            <>y(newText"12"),
            <>z(<>x(newText"3")),
        ], {"attr": "Yup"}.toXmlAttributes)

    test "Attributes with alias":
        type
            TestObj = object
                x {.xmlAttr, xmlName: "xx".}: int
        let obj = TestObj(x: 3)
        check obj.ser == "".newXmlTree([], {"xx": "3"}.toXmlAttributes)

    test "Flatten":
        type
            InnerObj = object
                x, y: int
            TestObj = object
                x {.xmlFlatten.}: InnerObj
                z: int
        let obj = TestObj(x: InnerObj(x: 2, y: 5), z: 1)
        check obj.ser == "".newXmlTree([
            <>x(newText"2"),
            <>y(newText"5"),
            <>z(newText"1")])

    test "Custom XML name":
        type
            TestObj = object
                x {.xmlName: "xx".}, y {.xmlName: "yz".}: int
        let obj = TestObj(x: 2, y: 10)
        check obj.ser == "".newXmlTree([
            <>xx(newText"2"),
            <>yz(newText"10")])

    test "Optional value":
        type
            TestObj = object
                x: Option[int]
        check TestObj(x: none(int)).ser == "".newXmlTree([])
        check TestObj(x: some(3)).ser == "".newXmlTree([<>x(newText"3")])

    test "Sequential value":
        type
            TestObj = object
                x: seq[int]
                y: seq[string]
        let obj = TestObj(x: @[3, 4, 2], y: @["Heyo"])
        check obj.ser == "".newXmlTree([
            <>x(newText"3"),
            <>x(newText"4"),
            <>x(newText"2"),
            <>y(newText"Heyo")])

    test "Datetime":
        type TestObj = object
            x: DateTime
        let dt = dateTime(2020, mJan, 21, 11, 21, zone = utc())
        let obj = TestObj(x: dt)
        check obj.ser == "".newXmlTree([
            <>x(newText"2020-01-21T11:21:00Z")])

    # TODO
    #test "Unions":
    #    type TestObj = object
    #        x: int
    #        case y: bool
    #        of false: a: int
    #        of true: b: string
    #    let obj = TestObj(x: 1, y: true, b: "Yo")
    #    check obj.ser == "".newXmlTree([
    #        <>x(newText"1"),
    #        <>b(newText"Yo")])
