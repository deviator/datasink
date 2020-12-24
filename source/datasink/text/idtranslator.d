module datasink.text.idtranslator;

import datasink.base;
import datasink.text.output;

interface IdTranslator
{
const:
    void translateId(TextBuffer o, const ScopeStack ss, Ident id);
}

class IdNoTranslator : IdTranslator
{
const override:
    void translateId(TextBuffer o, const ScopeStack ss, Ident id)
    {
        id.visit!(
            (typeof(null)) { },
            (string name) { o.put(name); },
            (ulong index) { formattedWrite(o, "[%d]", index); },
            (AAKey _) { o.put("key"); },
            (AAValue _) { o.put("val"); },
        );
    }
}

class SimpleMapIdTranslator : IdTranslator
{
    string[string] tr;
    this(string[string] m) pure { tr = m.dup; }

const override:
    void translateId(TextBuffer o, const ScopeStack ss, Ident id)
    {
        id.visit!(
            (typeof(null)) { },
            (string name) { put(o, tr.get(name, name)); },
            (ulong index) { formattedWrite(o, "[%d]", index); },
            (AAKey _) { o.put(tr.get("key", "key")); },
            (AAValue _) { o.put(tr.get("val", "val")); },
        );
    }
}
