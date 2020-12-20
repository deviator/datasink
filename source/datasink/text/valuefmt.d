module datasink.text.valuefmt;

import datasink.base;
import datasink.text.output;

interface ValueFormatter
{
    package import std.traits : EnumMembers;

    // не const потому что могут исп. промежуточные буфферы
    void formatValue(TextOutput o, const ScopeStack ss, in Value v);
}

/// всегда печатает как `%s`
class SimpleValueFormatter : ValueFormatter
{
override:
    void formatValue(TextOutput o, const ScopeStack, in Value v)
    { v.visit!(x => formattedWrite(o, "%s", x)); }
}
