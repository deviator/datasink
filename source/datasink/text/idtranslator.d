module datasink.text.idtranslator;

import datasink.base;

interface IdTranslator
{
    alias ScopeL = const(Scope[]);
const:
    string translateId(scope ScopeL scopeStack, string id);
}

class IdNoTranslator : IdTranslator
{
const override:
    string translateId(scope ScopeL scopeStack, string id)
    { return id; }
}

class SimpleMapIdTranslator : IdTranslator
{
    string[string] tr;
    this(string[string] m) pure { tr = m.dup; }

const override:
    string translateId(scope ScopeL scopeStack, string id)
    { return tr.get(id, id); }
}
