module datasink.text.valuefmt;

import datasink.base;
import datasink.text.output;

interface ValueFormatter
{
    package import std.traits : EnumMembers;

    // не const потому что могут исп. промежуточные буфферы
    void formatValue(TextOutputRef o,
                     scope const(Scope[]) scopeStack,
                     string id,
                     in Value v);
}

/// всегда печатает как `%s`
class SimpleValueFormatter : ValueFormatter
{
override:
    void formatValue(TextOutputRef output,
                     scope const(Scope[]) scopeStack,
                     string id,
                     in Value v)
    {
        v.visit!(x => formattedWrite(output, "%s", x));
    }
}
