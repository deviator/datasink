module datasink.typedesc;

import datasink.value;
import std.typecons : Tuple;

version (use_taggedalgebraic)
{
    private union ValueDscBase
    {
        typeof(null) unkn;
        Value.Kind   base;
        string       comp; /// name of complex (scope) type
    }

    alias ValueDsc = TaggedAlgebraic!ValueDscBase;
}
else
version (use_sumtype)
{
    alias ValueDsc = SumType!(
        typeof(null),
        size_t, // type index
        string,
    );
}
else
version (use_mir_algebraic)
{
    alias ValueDsc = TaggedVariant!(
        ["unkn", "base", "comp"],
        typeof(null),
        Value.Kind,
        string
    );
}
else
version (use_tagged_union)
{
    alias ValueDsc = TaggedUnion!(
        typeof(null),
        size_t,
        string
    );
}

/+
    Для типов, чьё описание до конца не извесно использовать `unkn`, а
    объект описания типа ObjectDsc конструировать "вручную" не на основе
    известно структуры

    Можно добавить флаг проверки соответствия вводимых данных описаню типа
 +/
struct ObjectDsc
{
    struct FieldDsc
    {
        ValueDsc    type;
        string      name; // name of field
    }

    string      name; // name of struct
    FieldDsc[]  fields;
    bool        extendable; // for dynamic append fields
}

struct TupleDsc { ValueDsc[] elems; }

struct EnumDsc
{
    string      name; // name of enum

    TypeOfKind!Value basetype;

    struct MemberDsc
    {
        string name;
        Value value;
    }
    MemberDsc[] def;
}

struct AArrayDsc
{
    ValueDsc    key;
    ValueDsc    value;
}

struct DArrayDsc
{
    ValueDsc    elem;
}

struct SArrayDsc
{
    ulong       length;
    ValueDsc    elem;
}

struct TUnionDsc
{
    static if (algebraicLibHasEnumKind)
        EnumDsc     kind;

    TupleDsc    dsc;
}

version (use_taggedalgebraic)
{
    private union TypeDscBase
    {
        ObjectDsc       object;
        TupleDsc        tuple;
        DArrayDsc       dArray;
        SArrayDsc       sArray;
        AArrayDsc       aArray;
        TUnionDsc       tUnion;
        EnumDsc         enumEl;
    }

    alias TypeDsc = TaggedUnion!TypeDscBase;
}

version (use_sumtype)
{
    alias TypeDsc = SumType!(
        ObjectDsc,
        TupleDsc,
        DArrayDsc,
        SArrayDsc,
        AArrayDsc,
        TUnionDsc,
        EnumDsc,
    );
}

version (use_mir_algebraic)
{
    alias TypeDsc = TaggedVariant!(
        ["object", "tuple",  "dArray",
         "sArray", "aArray", "tUnion",
         "enumEl"],

        ObjectDsc,
        TupleDsc,
        DArrayDsc,
        SArrayDsc,
        AArrayDsc,
        TUnionDsc,
        EnumDsc,
    );
}

version (use_tagged_union)
{
    alias TypeDsc = TaggedUnion!(
        ObjectDsc,
        TupleDsc,
        DArrayDsc,
        SArrayDsc,
        AArrayDsc,
        TUnionDsc,
        EnumDsc,
    );
}

template makeTypeDsc(T)
{
    import std : EnumMembers, map, array, OriginalType, to, ElementType;
    import std.traits : isStaticArray,
                        isDynamicArray,
                        isAssociativeArray,
                        KeyType,
                        ValueType;

    template nameOf(R) { enum nameOf = R.stringof; }

    ValueDsc valueDsc(X)()
    {
        enum ind = getKindIndex!(X, Value);
        static if (ind < 0) return ValueDsc(nameOf!X);
        else return ValueDsc(cast(ulong)getKindByIndex!(ind, Value));
    }

    TypeDsc impl()
    {
        static if (is(T == enum))
        {
            alias X = OriginalType!T;
            enum kind = getKindByType!(X, Value);
            
            return TypeDsc(EnumDsc(
                nameOf!T,
                kind,
                [EnumMembers!T]
                    .map!(a => EnumDsc.MemberDsc(a.to!string, Value(cast(X)a)))
                    .array
            ));
        }
        else static if (isStaticArray!T)
        {
            return TypeDsc(SArrayDsc(
                T.length,
                valueDsc!(ElementType!T)
            ));
        }
        else static if (isDynamicArray!T)
        {
            return TypeDsc(DArrayDsc(valueDsc!(ElementType!T)));
        }
        else static if (isAssociativeArray!T)
        {
            return TypeDsc(AArrayDsc(
                valueDsc!(KeyType!T),
                valueDsc!(ValueType!T)
            ));
        }
        else static if (isAlgebraicType!T)
        {
            enum dsc = makeTypeDsc!(Tuple!(Types!T)).getValue!TupleDsc;

            static if (algebraicLibHasEnumKind)
            {
                enum el = makeTypeDsc!(TypeOfKind!T).get!EnumDsc;
                return TypeDsc(TUnionDsc(el, dsc));
            }
            else return TypeDsc(TUnionDsc(dsc));
        }
        else static if (is(T == Tuple!X, X...))
        {
            TupleDsc r;

            foreach (i, v; T.init.tupleof)
            {
                alias V = typeof(T.tupleof[i]);
                r.elems ~= valueDsc!V;
            }

            return TypeDsc(r);
        }
        else static if (is(T == struct) || is(T == union))
        {
            auto r = ObjectDsc(T.stringof, [], false);

            foreach (i, v; T.init.tupleof)
            {
                alias V = typeof(T.tupleof[i]);
                enum name = __traits(identifier, T.tupleof[i]);
                r.fields ~= ObjectDsc.FieldDsc(valueDsc!V, name);
            }

            return TypeDsc(r);
        }
        else static assert(0, "unsupported type: " ~ T.stringof);
    }

    enum makeTypeDsc = impl();
}

unittest
{

    enum Foo
    {
        one = "ONE",
        two = "TWO",
    }

    static struct Bar
    {
        Foo foo;
        string x;
        struct IN
        {
            byte one;
            ushort two;
        }
        IN inField;
        IN[] arr1;
        Foo[10] arr2;
        int[string] arr3;
        int[] arr4;
    }

    import std : stderr;

    enum barDsc = makeTypeDsc!Bar;
    static assert (barDsc.kindIs!ObjectDsc, "bar is not an object");
    auto barDscObj = barDsc.getValue!ObjectDsc;
    //assert (barDscObj.name == "Bar"); ??
    assert (barDscObj.fields.length == 7);

    assert (barDscObj.fields[0].type.kindIs!string);
    // assert (barDscObj.fields[0].type.getValue!string == "Foo"); ??
    assert (barDscObj.fields[0].name == "foo");

    assert (barDscObj.fields[1].type.kindIs!(TypeOfKind!Value));
    assert (barDscObj.fields[1].type.getValue!(TypeOfKind!Value) == getKindByType!(string, Value));
    assert (barDscObj.fields[1].name == "x");

    assert (barDscObj.fields[2].type.kindIs!string);
    //assert (barDscObj.fields[2].type.getValue!string == "Bar.IN"); ?? or "IN"
    assert (barDscObj.fields[2].name == "inField");

    assert (barDscObj.fields[3].type.kindIs!string);
    //assert (barDscObj.fields[3].type.getValue!string == "IN[]"); ??
    assert (barDscObj.fields[3].name == "arr1");

    assert (barDscObj.fields[4].type.kindIs!string);
    //assert (barDscObj.fields[4].type.getValue!string == "Foo[10]"); ??
    assert (barDscObj.fields[4].name == "arr2");

    assert (barDscObj.fields[5].type.kindIs!string);
    //assert (barDscObj.fields[5].type.getValue!string == "int[string]"); ??
    assert (barDscObj.fields[5].name == "arr3");

    assert (barDscObj.fields[6].type.kindIs!string);
    //assert (barDscObj.fields[6].type.getValue!string == "int[]"); ??
    assert (barDscObj.fields[6].name == "arr4");


    enum barINDsc = makeTypeDsc!(Bar.IN);
    static assert (barINDsc.kindIs!ObjectDsc);
    auto barINDscObj = barINDsc.getValue!ObjectDsc;
    assert (barINDscObj.fields.length == 2);

    assert (barINDscObj.fields[0].type.kindIs!(TypeOfKind!Value));
    assert (barINDscObj.fields[0].type.getValue!(TypeOfKind!Value) == getKindByType!(byte, Value));
    assert (barINDscObj.fields[0].name == "one");

    assert (barINDscObj.fields[1].type.kindIs!(TypeOfKind!Value));
    assert (barINDscObj.fields[1].type.getValue!(TypeOfKind!Value) == getKindByType!(ushort, Value));
    assert (barINDscObj.fields[1].name == "two");

    enum fooDsc = makeTypeDsc!Foo;
    static assert (fooDsc.kindIs!EnumDsc);

    auto fooDscEnum = fooDsc.getValue!EnumDsc;

    assert (fooDscEnum.basetype == getKindByType!(string, Value));
    assert (fooDscEnum.def.length == 2);
    assert (fooDscEnum.def[0] == EnumDsc.MemberDsc("one", Value("ONE")));
    assert (fooDscEnum.def[1] == EnumDsc.MemberDsc("two", Value("TWO")));

    enum arr1Dsc = makeTypeDsc!(typeof(Bar.arr1));
    static assert (arr1Dsc.kindIs!DArrayDsc);

    enum arr2Dsc = makeTypeDsc!(typeof(Bar.arr2));
    static assert (arr2Dsc.kindIs!SArrayDsc);

    enum arr3Dsc = makeTypeDsc!(typeof(Bar.arr3));
    static assert (arr3Dsc.kindIs!AArrayDsc);

    enum valDsc = makeTypeDsc!Value;
    static assert (valDsc.kindIs!TUnionDsc);

    alias Tup = Tuple!(Foo, string, long);

    enum tupDsc = makeTypeDsc!Tup;
    static assert (tupDsc.kindIs!TupleDsc);

    auto tupDscTup = tupDsc.getValue!TupleDsc;
    assert (tupDscTup.elems.length == 3);
    assert (tupDscTup.elems[0].kindIs!string);
    assert (tupDscTup.elems[1].getValue!(TypeOfKind!Value) == getKindByType!(string, Value));
    assert (tupDscTup.elems[2].getValue!(TypeOfKind!Value) == getKindByType!(long, Value));

    version (test_print)
    {
        version (use_taggedalgebraic)
        {
            stderr.writeln(barDsc.objectValue);
            stderr.writeln(barINDsc.objectValue);

            barINDsc.visit!(
                (ObjectDsc d) => stderr.writeln(d),
                _ => stderr.writeln("??")
            );

            barDsc.visit!(v => stderr.writeln(v));
            
            stderr.writeln(fooDsc);
        }
        version (use_sumtype)
        {
            barDsc.match!(
                (ObjectDsc d) => stderr.writeln(d),
                _ => stderr.writeln("??")
            );
            barINDsc.match!(
                (ObjectDsc d) => stderr.writeln(d),
                _ => stderr.writeln("??")
            );

            barDsc.match!(v => stderr.writeln(v));
            fooDsc.match!(v => stderr.writeln(v));
            tupDsc.match!(v => stderr.writeln(v));
            arr1Dsc.match!(v => stderr.writeln(v));
            arr2Dsc.match!(v => stderr.writeln(v));
            arr3Dsc.match!(v => stderr.writeln(v));
            valDsc.match!(v => stderr.writeln(v));
        }
        version (use_mir_algebraic)
        {
            stderr.writeln(barDsc.get!ObjectDsc);
            stderr.writeln(barINDsc.get!ObjectDsc);

            barINDsc.visit!(
                (ObjectDsc d) => stderr.writeln(d),
                _ => stderr.writeln("??")
            );

            barDsc.visit!(v => stderr.writeln(v));

            stderr.writeln(fooDsc); // not print fields
            fooDsc.visit!(v => stderr.writeln(v));
            tupDsc.visit!(v => stderr.writeln(v));
            arr1Dsc.visit!(v => stderr.writeln(v));
            arr2Dsc.visit!(v => stderr.writeln(v));
            arr3Dsc.visit!(v => stderr.writeln(v));
            valDsc.visit!(v => stderr.writeln(v));
        }
        version (use_tagged_union)
        {
            stderr.writeln(barDsc.get!ObjectDsc);
            stderr.writeln(barINDsc.get!ObjectDsc);

            stderr.writeln(fooDsc);
            stderr.writeln(tupDsc);
            stderr.writeln(arr1Dsc);
            stderr.writeln(arr2Dsc);
            stderr.writeln(arr3Dsc);
            stderr.writeln(valDsc);
            // no visit or match
        }
    }
}
