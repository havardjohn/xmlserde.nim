import std/[xmltree, parsexml, unittest, options, streams, times, strutils]
import xmlserde
import results

suite "Deserialization":
    test "Basic object deserialization":
        type
            TestObj = object
                a: int
        let xml = $(<>a(newText"3"))
        check xml.deserString[:TestObj].get == TestObj(a: 3)

    # NOTE: `xmlAttr` is ignored on deserialization. See serializing tests for
    # usage.
    test "Attributes":
        type
            ChildObj = object
                a {.xmlAttr.}: int
                text {.xmlText.}: string
            TestObj = object
                x: ChildObj
        let xml = $(<>x(a = "3", newText"Hello"))
        check xml.deserString[:TestObj].get == TestObj(x: ChildObj(a: 3, text: "Hello"))

    test "Only attribute":
        type
            ChildObj = object
                a {.xmlAttr.}: string
            TestObj = object
                x: ChildObj
        # xmlElementOpen, xmlAttribute, xmlElementClose, xmlElementEnd
        let xml = $(<>x(a = "3"))
        check xml.deserString[:TestObj].get == TestObj(x: ChildObj(a: "3"))

    test "2 attributes":
        type
            ChildObj = object
                a {.xmlAttr.}: string
                b {.xmlAttr.}: string
            TestObj = object
                x: ChildObj
        # xmlElementOpen, xmlAttribute, xmlElementClose, xmlElementEnd
        let xml = $(<>x(a = "3", b = "4"))
        check xml.deserString[:TestObj].get == TestObj(x: ChildObj(a: "3", b: "4"))

    test "Many fields":
        type
            TestObj = object
                x, y: int
                z: string
        let xml = $(<>root(
            <>x(newText"1"),
            <>y(newText"2"),
            <>z(newText"World")))
        check xml.deserString[:TestObj]("root").get == TestObj(x: 1, y: 2, z: "World")

    test "Flatten deserialization":
        type
            InnerObj = object
                x, y: int
            TestObj = object
                x {.xmlFlatten.}: InnerObj
                z: int
        let xml = $(<>root(
            <>x(newText"1"),
            <>y(newText"2"),
            <>z(newText"4")))
        check xml.deserString[:TestObj]("root").get == TestObj(x: InnerObj(x: 1, y: 2), z: 4)

    test "Custom XML name":
        type
            TestObj = object
                x {.xmlName: "xyz".}: int
        let xml = $(<>xyz(newText"4"))
        check xml.deserString[:TestObj].get == TestObj(x: 4)

    test "Enum":
        type
            TestEnum = enum
                aeOne = "one"
                aeTwo = "twoo"
        let xml = $(<>x(newText"twoo"))
        check xml.deserString[:TestEnum]("x").get == aeTwo

    # NOTE: Cannot test non-UTC datetimes, because std/times only supports UTC
    # or local timezones.
    test "UTC datetime":
        type TestObj = object
            x: DateTime
        let xml = $(<>x(newText"2020-01-02T11:00:00Z"))
        check xml.deserString[:TestObj].get == TestObj(x: dateTime(2020, mJan, 2, 11, zone = utc()))

    test "Optional some":
        type TestObj = object
            x: Option[int]
        let xml = $(<>x(newText"3"))
        check xml.deserString[:TestObj].get == TestObj(x: some(3))

    test "Optional none":
        type TestObj = object
            x: Option[int]
        let xml = $("".newXmlTree([]))
        check xml.deserString[:TestObj].get == TestObj(x: none(int))

    test "Sequential":
        type TestObj = object
            x: seq[int]
        let xml = $(<>root(
            <>x(newText"2"),
            <>x(newText"3"),
            <>x(newText"1")))
        check xml.deserString[:TestObj]("root").get == TestObj(x: @[2, 3, 1])

    test "Mixed sequential":
        type TestObj = object
            x: seq[int]
            y: int
        let xml = $(<>root(
            <>x(newText"2"),
            <>y(newText"3"),
            <>x(newText"1")))
        check xml.deserString[:TestObj]("root").get == TestObj(x: @[2, 1], y: 3)

    test "Unparsable primitive generates error":
        type TestObj = object
            x: int16
        let xml = $(<>root(
            <>x(newText"600000")))
        check xml.deserString[:TestObj]("root").isErr

    test "Missing fields generate an error":
        type TestObj = object
            x, y: int16
        let xml = $(<>root(
            <>x(newText"321")))
        check xml.deserString[:TestObj]("root").error.contains"TestObj.y"

    test "Missing fields in flattened object generate an error":
        type
            InnerObj = object
                x, y: int16
            TestObj = object
                z {.xmlFlatten.}: InnerObj
        let xml = $(<>root(
            <>y(newText"421")))
        check xml.deserString[:TestObj]("root").error.contains"InnerObj.x"

    test "Missing lists don't generate an error":
        type TestObj = object
            x, y: seq[int16]
        let xml = $(<>root(
            <>x(newText"321")))
        check xml.deserString[:TestObj]("root").get == TestObj(x: @[321.int16], y: @[])

    # The `<z>(<y>...)` tests that `TestObj.y` is not overwritten with `z.y`'s
    # value; tests that nested ignoring is properly handled.
    test "XML not in schema is ignored":
        type TestObj = object
            y: string
        let xml = $(<>root(
            <>x(a = "someAttr", newText"ValueX"),
            <>y(newText"Hello"),
            <>z(<>y(newText"123"))))
        check xml.deserString[:TestObj]("root").get == TestObj(y: "Hello")

    test "Skipping field `xmlSkipDeser`":
        type TestObj = object
            x {.xmlSkipDeser.}: int
            y: string
        let xml = $(<>root(
            <>y(newText"Hi")))
        check xml.deserString[:TestObj]("root").get == TestObj(x: 0, y: "Hi")

    test "Skipping field `xmlSkip`":
        type TestObj = object
            x {.xmlSkip.}: int
            y: string
        let xml = $(<>root(
            <>y(newText"Hi")))
        check xml.deserString[:TestObj]("root").get == TestObj(x: 0, y: "Hi")

# XXX: `seq[Option[T]]` may not be possible. It is however not a type that ever
# appears from structures from XSD.

suite "Unions":
    setup:
        type TestObj = object
            x: int
            case y: uint8
            of 0: a: string
            of 1: b: int
            else: discard

    # NOTE: It is required that the XML field for the discriminator comes
    # before the actual union field.
    test "Deserialize the discriminator":
        let xml = $(<>root(
            <>x(newText"3"),
            <>y(newText"1"),
            <>b(newText"2")))
        check xml.deserString[:TestObj]("root").get.repr == TestObj(x: 3, y: 1, b: 2).repr

    test "Fail when union field is not deserialized":
        let xml2 = $(<>root(
            <>x(newText"3"),
            <>y(newText"1")))
        check xml2.deserString[:TestObj]("root").isErr

suite "Complex unions":
    test "Standard":
        type TestObj = object
            case x {.xmlSkipDeser.}: uint8
            of 0: y: int16
            of 1: z: string
            else: discard
        let xml = $(<>root(
            <>z(newText"Hello")))
        check $xml.deserString[:TestObj]("root").get == $TestObj(x: 1, z: "Hello")

    test "Successful use of `xmlName`":
        type TestObj = object
            case x {.xmlSkipDeser.}: uint8
            of 0: y {.xmlName: "Hello".}: int8
            of 1: z: string
            of 2: a: uint8
            else: discard
        let xml = $(<>root(
            <>Hello(newText"3")))
        check $xml.deserString[:TestObj]("root").get == $TestObj(x: 0, y: 3)

    test "Multiple fields in case":
        type TestObj = object
            case x {.xmlSkipDeser.}: uint8
            of 0: y: int8
            of 1:
                z: string
                a: seq[string]
                b {.xmlName: "betta".}: int8
            of 2: c: int8
            else: discard
        let xml = $(<>root(
            <>z(newText"AString"),
            <>betta(newText"8")))
        check $xml.deserString[:TestObj]("root").get == $TestObj(x: 1, z: "AString", a: @[], b: 8)

    test "XML fields matching different cases match last":
        type TestObj = object
            case x {.xmlSkipDeser.}: uint8
            of 0: y: int8
            of 1: z: int
            else: discard
        let xml = $(<>root(
            <>y(newText"3"),
            <>z(newText"5")))
        check $xml.deserString[:TestObj]("root").get == $TestObj(x: 1, z: 5)

    test "Flattened unions work":
        type
            InnerObj = object
                case x {.xmlSkip.}: uint8
                of 0: y: int
                of 1: z: int
                else: discard
            TestObj = object
                a: int
                b {.xmlFlatten.}: InnerObj
                c: string
        let xml = $(<>root(
            <>a(newText"3"),
            <>z(newText"10"),
            <>c(newText"Hey")))
        check $xml.deserString[:TestObj]("root").get == $TestObj(a: 3, b: InnerObj(x: 1, z: 10), c: "Hey")

    # In this test `c` is deserialized before the flattened union sets its
    # correct discriminant value. As such the number of fields in the whole
    # object changes mid-serialization (from 3 to 4).
    # This test prevents us from using `IntSet` to track the fields that are
    # deserialized as opposed to `seq[string]` (list of the deserialized keys).
    test "Holes":
        type
            InnerObj = object
                case x {.xmlSkip.}: uint8
                of 0: y: int
                of 1:
                    z1: int
                    z2: string
                else: discard
            TestObj = object
                a: string
                b {.xmlFlatten.}: InnerObj
                c: int
        let xml = $(<>root(
            <>a(newText"Hey1"),
            <>c(newText"3"),
            <>z1(newText"4"),
            <>z2(newText"5")))
        check $xml.deserString[:TestObj]("root").get == $TestObj(a: "Hey1", b: InnerObj(x: 1, z1: 4, z2: "5"), c: 3)

    test "Warning for mixed variant object compiles":
        type TestObj = object
            x: int
            case y {.xmlSkip.}: byte
            of 0: z1: int
            of 1: z2: int
            else: discard
        let xml = $(<>root(
            <>x(newText"3"),
            <>z2(newText"4")))
        check compiles(xml.deserString[:TestObj]("root"))

suite "Char data":
    test "Standard":
        type TestObj = object
            x: string
        let xml = "<root><x>He&apos;llo</x></root>"
        check xml.deserString[:TestObj]("root").get == TestObj(x: "He'llo")

    test "attribute":
        type
            ChildObj = object
                a {.xmlAttr.}: string
            TestObj = object
                x: ChildObj
        # xmlElementOpen, xmlAttribute, xmlElementClose, xmlElementEnd
        let xml = """<x a="He&lt;llo" />"""
        check xml.deserString[:TestObj].get == TestObj(x: ChildObj(a: "He<llo"))

    # The tested XML string is parsed into the following tokens:
    # xmlCharData("He"), xmlCharData(">"), xmlWhitespace("  "),
    # xmlCharData("llo"). This peculiar occurrence of `xmlWhitespace` inside
    # what should be just `xmlCharData` tokens must be parsed correctly.
    test "Whitespace after escape sequence parses correctly":
        type TestObj = object
            x: string
        let xml = """<x>He&gt;  llo</x>"""
        check xml.deserString[:TestObj].get == TestObj(x: "He>  llo")
