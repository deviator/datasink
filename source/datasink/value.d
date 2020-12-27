module datasink.value;

public import mir.algebraic;

// 0 и 1 специализируются в bool вместо int, bool нужно обернуть
enum Bool : bool
{
    false_ = false,
    true_  = true,
}

alias Value = TaggedVariant!(
    ["nil", "str", "raw", "bit", "i8",  "u8",  "i16",
     "u16", "i32", "u32", "i64", "u64", "f32", "f64"],
    typeof(null),
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

import std.meta : staticIndexOf;
import std.traits : EnumMembers;

enum getKindIndex(X,T) = staticIndexOf!(X, T.AllowedTypes);

size_t getValueKindIndex(T, X)(in X val) if (isVariant!T)
{ return getKindIndex!(X,T); }

template getKindByIndex(ptrdiff_t index, T)
    if (isTaggedVariant!T && index >= 0)
{ enum getKindByIndex = EnumMembers!(T.Kind)[index]; }

template getKindByType(X, T) if (isTaggedVariant!T)
{ enum getKindByType = getKindByIndex!(getKindIndex!(X, T), T); }

template TypeByKind(T, alias kind)
    if (isTaggedVariant!T && is(typeof(kind) == T.Kind))
{
    import std : staticIndexOf, EnumMembers;
    alias TypeByKind = T.AllowedTypes[kind];
}
