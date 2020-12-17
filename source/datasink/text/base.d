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
    bool hasElems = false;

    TextOutput output;
    IdTranslator idtr;
    ValueFormatter vfmt;

    void insertSeparator() { put(output, ", "); }

    import std : Rebindable;

    Nullable!(Rebindable!(const(EnumDsc.MemberDsc[]))) enumMemberDef;

    void putScopeStart()
    {
        const top = scopeStack.top;
        //if (scopeStack.length > 1) printId(top.id);

        enum obj = "{ ";
        enum arr = "[ ";

        final switch (top.kind) with(top.Kind)
        {
            case object: case aArray: case tUnion:
                put(output, obj);
                break;
            case sArray: case dArray: case tuple:
                put(output, arr);
                break;
            case enumEl:
                enumMemberDef = top.get!EnumDsc.def;
                break;
        }
    }

    void putScopeEnd()
    {
        const top = scopeStack.top;

        enum obj = " }";
        enum arr = " ]";

        final switch (top.kind) with(top.Kind)
        {
            case object: case aArray: case tUnion:
                put(output, obj);
                break;
            case sArray: case dArray: case tuple:
                put(output, arr);
                break;
            case enumEl:
                enumMemberDef.nullify;
                break;
        }
    }

    override // BaseDataSink
    {
        void onPushScope()
        {
            if (hasElems) insertSeparator();
            hasElems = false;
            putScopeStart();
        }

        void onPopScope()
        {
            hasElems = true;
            putScopeEnd();
            if (scopeStack.length == 1)
            {
                output.endOfBlock();
                hasElems = false;
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
        if (hasElems) insertSeparator();
        put(output, idtr.translateId(scopeStack.data, id));
        put(output, ": ");
    }

    void putValue(in Value v)
    {
        if (enumMemberDef.isNull)
            vfmt.formatValue(output, scopeStack.data, "", v);
        else
        {
            auto x = enumMemberDef.get[v.get!uint].value;
            vfmt.formatValue(output, scopeStack.data, "", x);
        }
        hasElems = true;
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
