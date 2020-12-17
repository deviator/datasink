module datasink.value;


// 0 и 1 специализируются в bool вместо int, bool нужно обернуть
enum Bool : bool
{
    false_ = false,
    true_  = true,
}

enum UNKNOWNLIB = "not selected or unknown algebraic library";

version (use_taggedalgebraic)
{
    static assert (0, "doesn't work at compile time");

    public import taggedalgebraic;

    private union ValueBase
    {
        string          str;
        const(void)[]   raw;
        Bool            bit;
        byte            i8;
        ubyte           u8;
        short           i16;
        ushort          u16;
        int             i32;
        uint            u32;
        long            i64;
        ulong           u64;
        float           f32;
        double          f64;
    }

    alias Value = TaggedAlgebraic!ValueBase;
}
else
version (use_sumtype)
{
    public import sumtype;

    alias Value = SumType!(
        string,
        const(void)[],
        Bool,
        byte,
        ubyte,
        short,
        ushort,
        int,
        uint,
        long,
        ulong,
        float,
        double,
    );
}
else
version (use_mir_algebraic)
{
    public import mir.algebraic;

    alias Value = TaggedVariant!(
        ["str", "raw", "bit",
         "i8",  "u8",  "i16",
         "u16", "i32", "u32",
         "i64", "u64", "f32",
         "f64"],
        string,
        const(void)[],
        Bool,
        byte,
        ubyte,
        short,
        ushort,
        int,
        uint,
        long,
        ulong,
        float,
        double,
    );
}
else
version (use_tagged_union)
{
    public import tagged_union;

    alias Value = TaggedUnion!(
        string,
        const(void)[],
        Bool,
        byte,
        ubyte,
        short,
        ushort,
        int,
        uint,
        long,
        ulong,
        float,
        double,
    );
}
else
static assert(0, UNKNOWNLIB);

template isAlgebraicType(T)
{
    version (use_taggedalgebraic)
    {
        enum tUnion = is(T == TaggedUnion!X, X);
        enum tAlgebraic = is(T == TaggedAlgebraic!X, X);
        enum isAlgebraicType = tUnion || tAlgebraic;
    }
    else
    version (use_sumtype)
        enum isAlgebraicType = is(T == SumType!(X), X...);
    else
    version (use_mir_algebraic)
        enum isAlgebraicType = isTaggedVariant!T;
    else
    version (use_tagged_union)
        enum isAlgebraicType = is(T == TaggedUnion!X, X...);
}

template TypeOfKind(T) if (isAlgebraicType!T)
{
    version (use_taggedalgebraic)
        alias TypeOfKind =  T.Kind;
    else
    version (use_mir_algebraic)
        alias TypeOfKind =  T.Kind;
    else
    version (use_tagged_union)
        alias TypeOfKind =  size_t;
    else
    version (use_sumtype)
        alias TypeOfKind =  size_t;
}

bool algebraicLibHasEnumKind()
{
    version (use_taggedalgebraic) return true;
    else
    version (use_mir_algebraic) return true;
    else
    version (use_tagged_union) return false;
    else
    version (use_sumtype) return false;
    else
    static assert(0, UNKNOWNLIB);
}

template getKindIndex(X, T) if (isAlgebraicType!T)
{
    import std.meta : staticIndexOf;

    version (use_taggedalgebraic)
    {
        static if (is(T == TaggedAlgebraic!Y, Y))
            enum r = staticIndexOf!(X, T.UnionType.FieldTypes);
        else
            enum r = staticIndexOf!(X, T.FieldTypes);
    }
    else
    version (use_sumtype)
        enum r = staticIndexOf!(X, Value.Types);
    else
    version (use_mir_algebraic)
        enum r = staticIndexOf!(X, Value.AllowedTypes);
    else
    version (use_tagged_union)
        enum r = Value.IndexOf!X;
    else
    static assert(0, UNKNOWNLIB);

    enum getKindIndex = r;
}

template getKindByIndex(ptrdiff_t index, T) if (isAlgebraicType!T && index >= 0)
{
    import std.traits : EnumMembers;

    version (use_taggedalgebraic)
        enum r = EnumMembers!(T.Kind)[index];
    else
    version (use_sumtype)
        enum r = index;
    else
    version (use_mir_algebraic)
        enum r = EnumMembers!(T.Kind)[index];
    else
    version (use_tagged_union)
        enum r = index;
    else
    static assert(0, UNKNOWNLIB);

    enum getKindByIndex = r;
}

template getKindByType(X, T) if (isAlgebraicType!T)
{
    enum getKindByType = getKindByIndex!(getKindIndex!(X, T), T);
}

bool kindIs(X, T)(auto ref const T v) if (isAlgebraicType!T)
{
    version (use_taggedalgebraic) static assert (0, "NOTIMPL");
    else
    version (use_sumtype)
    {
        // match doesn't work with const
        return (cast()v).match!((X x) => true, _ => false);
    }
    else
    version (use_mir_algebraic) return v._is!X;
    else
    version (use_tagged_union) return v.isType!X;
    else
    static assert(0, UNKNOWNLIB);
}

auto getValue(X, T)(auto ref const T v) if (isAlgebraicType!T)
{
    version (use_taggedalgebraic) static assert (0, "NOTIMPL");
    else
    version (use_sumtype)
    {
        // match doesn't work with const
        return (cast()v).match!(
            (X x) => x,
            (_) {
                assert(0);
                return X.init;
            }
            );
    }
    else
    version (use_mir_algebraic) return v.get!X;
    else
    version (use_tagged_union) return v.get!X;
    else
    static assert(0, UNKNOWNLIB);
}

template Types(T) if (isAlgebraicType!T)
{
    version (use_taggedalgebraic)
    {
        static if (is(T == TaggedAlgebraic!Y, Y))
            alias Types = T.UnionType.FieldTypes;
        else
            alias Types = T.FieldTypes;
    }
    else
    version (use_sumtype) alias Types = T.Types;
    else
    version (use_mir_algebraic) alias Types = T.AllowedTypes;
    else
    version (use_tagged_union) alias Types = T.Types;
    else
    static assert(0, UNKNOWNLIB);
}
