module datasink.typedesc;

import datasink.value;
import std.typecons : Tuple;

alias ValueDsc = TaggedVariant!(
    ["unkn", "base", "comp"],
    typeof(null),
    Value.Kind,
    string
);

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
    bool        extendable = true; // for dynamic append fields
}

struct TupleDsc { ValueDsc[] elems; }

struct EnumDsc
{
    string      name; // name of enum

    Value.Kind basetype;

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
    EnumDsc     kind;
    TupleDsc    dsc;
}

alias TypeDsc = TaggedVariant!(
    ["value", "object", "tuple",  "dArray", "sArray",  "aArray",  "tUnion",  "enumEl"],
    Value.Kind, ObjectDsc, TupleDsc, DArrayDsc, SArrayDsc, AArrayDsc, TUnionDsc, EnumDsc,
);

template makeTypeDsc(T)
{
    import std : EnumMembers, map, array, OriginalType, to, ElementType, Unqual;
    import std.traits : isArray,
                        isStaticArray,
                        isDynamicArray,
                        isAssociativeArray,
                        KeyType,
                        ValueType;

    template nameOf(R) { enum nameOf = R.stringof; }

    ValueDsc valueDsc(X)()
    {
        //static if (is(typeof(Value(X.init))))
        //    return ValueDsc(Value(X.init).kind);
        //else
        //    return ValueDsc(nameOf!X);
        enum ind = getKindIndex!(Unqual!X, Value);
        static if (ind < 0) return ValueDsc(nameOf!X);
        else return ValueDsc(getKindByIndex!(ind, Value));
    }

    TypeDsc impl()
    {
        enum vdsc = valueDsc!T;
        static if (vdsc.kind == ValueDsc.Kind.base)
        {
            return TypeDsc(vdsc.get!(Value.Kind));
        }
        else
        static if (is(T == bool))
        {
            return TypeDsc(Value.Kind.bit);
        }
        else
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
        else
        static if (isArray!T && is(Unqual!(ElementType!T) == void))
        {
            return TypeDsc(Value.Kind.raw);
        }
        else
        static if (isStaticArray!T)
        {
            return TypeDsc(SArrayDsc(
                T.length,
                valueDsc!(ElementType!T)
            ));
        }
        else
        static if (isDynamicArray!T)
        {
            return TypeDsc(DArrayDsc(valueDsc!(ElementType!T)));
        }
        else
        static if (isAssociativeArray!T)
        {
            return TypeDsc(AArrayDsc(
                valueDsc!(KeyType!T),
                valueDsc!(ValueType!T)
            ));
        }
        else
        static if (isTaggedVariant!T)
        {
            enum dsc = makeTypeDsc!(Tuple!(T.AllowedTypes)).get!TupleDsc;
            enum el = makeTypeDsc!(T.Kind).get!EnumDsc;
            return TypeDsc(TUnionDsc(el, dsc));
        }
        else
        static if (is(T == Tuple!X, X...))
        {
            TupleDsc r;

            foreach (i, v; T.init.tupleof)
            {
                alias V = typeof(T.tupleof[i]);
                r.elems ~= valueDsc!V;
            }

            return TypeDsc(r);
        }
        else
        static if (is(T == struct) || is(T == union))
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
    enum intDsc = makeTypeDsc!int;

    static assert (intDsc.kind == TypeDsc.Kind.value);
    static assert (intDsc.get!(Value.Kind) == Value.Kind.i32);

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
    static assert (barDsc._is!ObjectDsc, "bar is not an object");
    auto barDscObj = barDsc.get!ObjectDsc;
    //assert (barDscObj.name == "Bar"); ??
    assert (barDscObj.fields.length == 7);

    assert (barDscObj.fields[0].type._is!string);
    // assert (barDscObj.fields[0].type.get!string == "Foo"); ??
    assert (barDscObj.fields[0].name == "foo");

    assert (barDscObj.fields[1].type._is!(Value.Kind));
    assert (barDscObj.fields[1].type.get!(Value.Kind) == getKindByType!(string, Value));
    assert (barDscObj.fields[1].name == "x");

    assert (barDscObj.fields[2].type._is!string);
    //assert (barDscObj.fields[2].type.get!string == "Bar.IN"); ?? or "IN"
    assert (barDscObj.fields[2].name == "inField");

    assert (barDscObj.fields[3].type._is!string);
    //assert (barDscObj.fields[3].type.get!string == "IN[]"); ??
    assert (barDscObj.fields[3].name == "arr1");

    assert (barDscObj.fields[4].type._is!string);
    //assert (barDscObj.fields[4].type.get!string == "Foo[10]"); ??
    assert (barDscObj.fields[4].name == "arr2");

    assert (barDscObj.fields[5].type._is!string);
    //assert (barDscObj.fields[5].type.get!string == "int[string]"); ??
    assert (barDscObj.fields[5].name == "arr3");

    assert (barDscObj.fields[6].type._is!string);
    //assert (barDscObj.fields[6].type.get!string == "int[]"); ??
    assert (barDscObj.fields[6].name == "arr4");


    enum barINDsc = makeTypeDsc!(Bar.IN);
    static assert (barINDsc._is!ObjectDsc);
    auto barINDscObj = barINDsc.get!ObjectDsc;
    assert (barINDscObj.fields.length == 2);

    assert (barINDscObj.fields[0].type._is!(Value.Kind));
    assert (barINDscObj.fields[0].type.get!(Value.Kind) == getKindByType!(byte, Value));
    assert (barINDscObj.fields[0].name == "one");

    assert (barINDscObj.fields[1].type._is!(Value.Kind));
    assert (barINDscObj.fields[1].type.get!(Value.Kind) == getKindByType!(ushort, Value));
    assert (barINDscObj.fields[1].name == "two");

    enum fooDsc = makeTypeDsc!Foo;
    static assert (fooDsc._is!EnumDsc);

    auto fooDscEnum = fooDsc.get!EnumDsc;

    assert (fooDscEnum.basetype == getKindByType!(string, Value));
    assert (fooDscEnum.def.length == 2);
    assert (fooDscEnum.def[0] == EnumDsc.MemberDsc("one", Value("ONE")));
    assert (fooDscEnum.def[1] == EnumDsc.MemberDsc("two", Value("TWO")));

    enum arr1Dsc = makeTypeDsc!(typeof(Bar.arr1));
    static assert (arr1Dsc._is!DArrayDsc);

    enum arr2Dsc = makeTypeDsc!(typeof(Bar.arr2));
    static assert (arr2Dsc._is!SArrayDsc);

    enum arr3Dsc = makeTypeDsc!(typeof(Bar.arr3));
    static assert (arr3Dsc._is!AArrayDsc);

    enum valDsc = makeTypeDsc!Value;
    static assert (valDsc._is!TUnionDsc);

    alias Tup = Tuple!(Foo, string, long);

    enum tupDsc = makeTypeDsc!Tup;
    static assert (tupDsc._is!TupleDsc);

    auto tupDscTup = tupDsc.get!TupleDsc;
    assert (tupDscTup.elems.length == 3);
    assert (tupDscTup.elems[0]._is!string);
    assert (tupDscTup.elems[1].get!(Value.Kind) == getKindByType!(string, Value));
    assert (tupDscTup.elems[2].get!(Value.Kind) == getKindByType!(long, Value));

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
