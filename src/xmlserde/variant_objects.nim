import std/[macros, sequtils]
import zero_functional
import common

# NOTE: When assigning to a case-of object and changing discriminant, the
# object constructor must be called; a direct assignment of the discriminant is
# a hard error (in spite of using `uncheckedAssign` pragma block).
# A consequence of this is that each time the discriminator is deserialized,
# the whole object is zero'd. This is a marginal problem for the union fields,
# but this affects the non-unions much more. Developers should therefore make
# their union objects their own objects, as opposed to putting unions into an
# object with existing fields. This thinking should be familiar to Rust
# developers.

func identDefsToIdent(def: NimNode): NimNode =
    def.expectKind nnkIdentDefs
    result =
        case def[0].kind
        of nnkIdent: def[0]
        of nnkPragmaExpr: def[0][0]
        else: def[0].expectKind {nnkIdent, nnkPragmaExpr}; nil
    result.expectKind nnkIdent

func getDiscriminant(obj: NimNode): NimNode =
    obj.expectKind nnkRecCase
    obj[0].expectKind nnkIdentDefs
    obj[0].identDefsToIdent

# Can return `nil`
func getRecCase(obj: NimNode): NimNode =
    obj.expectKind nnkObjectTy
    let recList = obj[^1]
    recList.expectKind nnkRecList
    recList.findChild(it.kind == nnkRecCase)

type ValueMap = object
    discrValue: NimNode
    objFields: seq[NimNode]

func ofBranchToMap(branch: NimNode): ValueMap =
    branch.expectKind nnkOfBranch
    let rawObjFields =
        case branch[1].kind
        of nnkRecList: branch[1][0..^1]
        of nnkIdentDefs: @[branch[1]]
        else: branch[1].expectKind {nnkRecList, nnkIdentDefs}; @[]
    ValueMap(
        discrValue: branch[0],
        objFields: rawObjFields.map(identDefsToIdent))

# NOTE: The possible `else` branch in the union is ignored. This is because
# there is no reasonable value for the discriminator to "activate" this
# branch at runtime. `high(T)` could work for integer discriminants, but
# does not necessarily work well with enum discriminants. It is however
# reasonable to let the developer take this into account in their data type
# design.
func getValueMap(obj: NimNode): seq[ValueMap] =
    obj.expectKind nnkRecCase
    result = obj[1..^2].map(ofBranchToMap)
    if obj[^1].kind == nnkOfBranch:
        result &= obj[^1].ofBranchToMap

#func getTypeInst(obj: NimNode): NimNode =
#    return obj.getTypeInst
#    obj.astGenRepr.debugEcho
#    obj.getTypeInst.astGenRepr.debugEcho
#    let sym = case obj.kind
#        of nnkSym: obj
#        of nnkHiddenDeref: obj[0]
#        of nnkDotExpr: obj.getTypeInst
#        else: obj.expectKind {nnkSym, nnkHiddenDeref}; nil
#    sym.expectKind nnkSym
#    let firstTyp = sym.getType
#    if firstTyp.kind == nnkSym:
#        firstTyp
#    else:
#        firstTyp[^1].expectKind nnkSym
#        firstTyp[^1]

func genOfBranch(obj, discrField, discrVal, objField: NimNode): NimNode =
    let objTyp = obj.getTypeInst
    nnkOfBranch.newTree(
        newLit xmlNameOf(objField, objField.strVal),
        quote do:
            if `obj`.`discrField` != `discrVal`:
                `obj` = `objTyp`(`discrField`: `discrVal`))

# Generate an `of`-branch for the `case-of`-statement for each possible union field.
func genOfBranches(obj, discriminant: NimNode, valueMap: seq[ValueMap]): seq[NimNode] =
    valueMap --> (mapping).
        map(mapping.objFields --> (objField).
            map(genOfBranch(obj, discriminant, mapping.discrValue, objField))).
        flatten()

macro isVariantAndNormal*(obj: typed): bool =
    ## `true` if object type of `obj` contains a case-of statement as well as
    ## ordinary non-case-of fields.
    let typeSym = obj.getTypeInst
    typeSym.expectKind nnkSym
    let recList = typeSym.getImpl[^1][^1] # -> type def -> nnkObjectTy -> nnkRecList
    recList.expectKind nnkRecList
    newLit (not recList.findChild(it.kind == nnkRecCase).isNil and
        not recList.findChild(it.kind == nnkIdentDefs).isNil)


macro deserUnion*(obj: typed, name: string) =
    ## Finds and makes the union field `name` in object `obj` active by making
    ## sure the discriminator is set accordingly.
    ##
    ## More specifically, if the discriminant is not assigned such that
    ## `obj`.`name` is assignable, then the object is recreated and the
    ## discriminant is set accordingly (i.e. zeroes the object).
    ##
    ## If the object does not have union fields, or the union field could not
    ## be found, this macro does nothing.
    let typ = obj.getTypeInst
    let recCase = typ.getImpl[^1].getRecCase
    if recCase.isNil:
        return
    let discriminant = recCase.getDiscriminant
    let valueMap = recCase.getValueMap

    result = nnkCaseStmt.newTree name
    for node in genOfBranches(obj, discriminant, valueMap):
        result.add node
    result.add nnkElse.newTree(nnkDiscardStmt.newTree(newEmptyNode()))
