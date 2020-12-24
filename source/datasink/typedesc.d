module datasink.typedesc;

import datasink.value;
import std.typecons : Tuple;

struct EnumDsc
{
    struct MemberDsc
    {
        string name;
        Value value;
    }
    MemberDsc[] def;
}

struct ObjectDsc { ulong length; }
struct TupleDsc { ulong length; }
struct AArrayDsc { }
struct DArrayDsc { }
struct SArrayDsc { ulong length; }
struct TUnionDsc { }

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

    Nullable!(Value.Kind) valueDsc(X)()
    {
        enum ind = getKindIndex!(Unqual!X, Value);
        static if (ind < 0) return typeof(return)(null);
        else return typeof(return)(getKindByIndex!(ind, Value));
    }

    TypeDsc impl()
    {
        enum vdsc = valueDsc!T;
        static if (!vdsc.isNull)
        {
            return TypeDsc(vdsc.get);
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
            
            return TypeDsc(EnumDsc(
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
            return TypeDsc(SArrayDsc(T.length));
        }
        else
        static if (isDynamicArray!T)
        {
            return TypeDsc(DArrayDsc.init);
        }
        else
        static if (isAssociativeArray!T)
        {
            return TypeDsc(AArrayDsc.init);
        }
        else
        static if (isTaggedVariant!T)
        {
            return TypeDsc(TUnionDsc.init);
        }
        else
        static if (is(T == Tuple!X, X...))
        {
            return TypeDsc(TupleDsc(T.tupleof.length));
        }
        else
        static if (is(T == struct) || is(T == union))
        {
            return TypeDsc(ObjectDsc(T.tupleof.length));
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


    enum barINDsc = makeTypeDsc!(Bar.IN);
    static assert (barINDsc._is!ObjectDsc);

    enum fooDsc = makeTypeDsc!Foo;
    static assert (fooDsc._is!EnumDsc);

    auto fooDscEnum = fooDsc.get!EnumDsc;

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

}
