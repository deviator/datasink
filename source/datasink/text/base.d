module datasink.text.base;

package
{
    import datasink.base;
    import datasink.text.valuefmt;
    import datasink.text.idtranslator;
    import datasink.text.output;

    import datasink.util : or;

    import std.format : formattedWrite;
    import std.exception : enforce;
}

class BaseTextDataSink : BaseDataSink
{
protected:
    bool needSeparator = false;

    TextOutput output;
    IdTranslator idtr;
    ValueFormatter vfmt;

    void insertSeparator() { put(output, ", "); }
    void insertIdentSep() { put(output, ": "); }
    void printString(scope const(char[]) str) { put(output, str); }

    import std : Rebindable;

    Nullable!(Rebindable!(const(EnumDsc.MemberDsc[]))) enumMemberDef;

    ref const(Scope) scopeStackTop() const { return scopeStack.top; }

    void putScopeStrings(string obj, string arr, scope void delegate() onEnum)
    {
        const top = scopeStackTop;

        final switch (top.kind) with(top.Kind)
        {
            case object: case aArray: case tUnion:
                put(output, obj);
                break;
            case sArray: case dArray: case tuple:
                put(output, arr);
                break;
            case enumEl:
                onEnum();
                break;
        }
    }

    void putScopeStart()
    {
        putScopeStrings("{ ", "[ ",
            { enumMemberDef = scopeStackTop.get!EnumDsc.def; });
    }

    void putScopeEnd()
    {
        putScopeStrings(" }", " ]", { enumMemberDef.nullify; });
    }

    override // BaseDataSink
    {
        void onPushScope()
        {
            if (needSeparator) insertSeparator();
            needSeparator = false;
            putScopeStart();
        }

        void onPopScope()
        {
            needSeparator = true;
            putScopeEnd();
            if (scopeStack.length == 1)
            {
                output.endOfBlock();
                needSeparator = false;
            }
        }
    }
    
public:

    this(TextOutput o, IdTranslator tr, ValueFormatter vf)
    {
        output = enforce(o, "output is null");
        idtr = tr.or(new IdNoTranslator);
        vfmt = vf.or(new SimpleValueFormatter);
    }

override:

    void putIdent(string id)
    {
        if (needSeparator) insertSeparator();
        printString(idtr.translateId(scopeStack.data, id));
        insertIdentSep();
        needSeparator = false;
    }

    void putValue(in Value v)
    {
        if (needSeparator) insertSeparator();
        if (enumMemberDef.isNull)
            vfmt.formatValue(output, scopeStack.data, "", v);
        else
        {
            auto x = enumMemberDef.get[v.get!uint].value;
            vfmt.formatValue(output, scopeStack.data, "", x);
        }
        needSeparator = true;
    }
}

unittest
{
    auto ao = new AppenderOutput;

    auto tds = new BaseTextDataSink(ao, null, null);

    auto brds = new BaseRootDataSink(tds);

    static struct Foo
    {
        int first;
        string second;
    }

    brds.putData(Foo(10, "hello"));
    assert (ao.data[] == "{ first: 10, second: hello }");
    ao.data.clear();

    brds.putData(Foo(42, "world"));
    assert (ao.data[] == "{ first: 42, second: world }");
    ao.data.clear();
}
