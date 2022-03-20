import std/[xmltree, parsexml, unittest, options, streams, times]
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

    test "Serialize bad primitive":
        type TestObj = object
            x: int16
        let xml = $(<>root(
            <>x(newText"600000")))
        check xml.deserString[:TestObj]("root").isErr

# XXX: `seq[Option[T]]` may not be possible. It is however not a type that ever
# appears from structures from XSD.

# TODO
#test "Unions":
#    type TestObj = object
#        x: int
#        case y: bool
#        of false: a: int
#        of true: b: string
#    let xml = $(<>root(
#        <>x(newText"1"),
#        <>b(newText"Yo")))
#    check xml.deserString[:TestObj]("root") == TestObj(x: 1, y: true, b: "Yo")
