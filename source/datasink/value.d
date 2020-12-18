module datasink.value;

// 0 и 1 специализируются в bool вместо int, bool нужно обернуть
enum Bool : bool
{
    false_ = false,
    true_  = true,
}

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

template getKindIndex(X, T) if (isTaggedVariant!T)
{
    import std.meta : staticIndexOf;
    enum r = staticIndexOf!(X, Value.AllowedTypes);
    enum getKindIndex = r;
}

template getKindByIndex(ptrdiff_t index, T)
    if (isTaggedVariant!T && index >= 0)
{
    import std.traits : EnumMembers;
    enum r = EnumMembers!(T.Kind)[index];
    enum getKindByIndex = r;
}

template getKindByType(X, T) if (isTaggedVariant!T)
{
    enum getKindByType = getKindByIndex!(getKindIndex!(X, T), T);
}

template TypeByKind(T, alias kind)
    if (isTaggedVariant!T && is(typeof(kind) == T.Kind))
{
    import std : staticIndexOf, EnumMembers;
    alias TypeByKind = T.AllowedTypes[kind];
}
