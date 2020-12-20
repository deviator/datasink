module datasink.text.idtranslator;

import datasink.base;
import datasink.text.output;

interface IdTranslator
{
const:
    void translateId(TextOutputRef o, const ScopeStack ss, Ident id);
}

class IdNoTranslator : IdTranslator
{
const override:
    void translateId(TextOutputRef o, const ScopeStack ss, Ident id)
    {
        id.visit!(
            (typeof(null)) { },
            (string name) { put(o, name); },
            (ulong index) { formattedWrite(o, "[%d]", index); },
            (AAData aa) { formattedWrite(o, "%s", aa==AAData.key ? "key" : "val"); }
        );
    }
}

class SimpleMapIdTranslator : IdTranslator
{
    string[string] tr;
    this(string[string] m) pure { tr = m.dup; }

const override:
    void translateId(TextOutputRef o, const ScopeStack ss, Ident id)
    {
        id.visit!(
            (typeof(null)) { },
            (string name) { put(o, tr.get(name, name)); },
            (ulong index) { formattedWrite(o, "[%d]", index); },
            (AAData aa)
            {
                formattedWrite(o, "%s",
                    aa==AAData.key ? tr.get("key", "key") :
                                     tr.get("val", "val"));
            }
        );
    }
}
