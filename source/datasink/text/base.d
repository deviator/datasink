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

class ExampleTextDataSink : BaseDataSink
{
protected:
    bool needSeparator = false;

    bool needIdent() const @property
    {
        if (needIdentStack.empty) return false;
        return needIdentStack.top;
    }
    Stack!bool needIdentStack;

    AppenderOutputRef idTmpOutput;
    TextOutput output;
    IdTranslator idtr;
    ValueFormatter vfmt;

    void printValueSep() { put(output, ", "); }
    void printIdentSep() { put(output, ": "); }
    void printString(scope const(char[]) str) { put(output, str); }

    void printIdent(Ident id)
    {
        idTmpOutput.clear();
        idtr.translateId(idTmpOutput, scopeStack, id);
        printString(idTmpOutput.data);
        printIdentSep();
    }

    import std : Rebindable;

    alias EnumMemberDef = Nullable!(Rebindable!(const(EnumDsc.MemberDsc[])));

    EnumMemberDef enumMemberDef;

    ref const(Scope) scopeStackTop() const { return scopeStack.top; }

    void putScopeStrings(bool start, string obj, string arr)
    {
        const top = scopeStackTop;

        void onStartPushNeedIdent(bool n)
        {
            if (start) needIdentStack.push(n);
            else needIdentStack.pop();
        }

        final switch (top.dsc.kind) with(top.dsc.Kind)
        {
            case value: break;
            case object: case tUnion:
                put(output, obj);
                onStartPushNeedIdent(true);
                break;
            case aArray:
                put(output, obj);
                onStartPushNeedIdent(false);
                break;
            case sArray: case dArray: case tuple:
                put(output, arr);
                onStartPushNeedIdent(false);
                break;
            case enumEl:
                if (!start) enumMemberDef.nullify; 
                else enumMemberDef = scopeStackTop.dsc.get!EnumDsc.def;
                break;
        }
    }

    void putScopeStart() { putScopeStrings(true, "{ ", "[ "); }

    void putScopeEnd() { putScopeStrings(false, " }", " ]"); }

    override // BaseDataSink
    {
        void onPushScope()
        {
            if (needSeparator) printValueSep();
            needSeparator = false;
            if (needIdent) printIdent(scopeStack.top.id);
            putScopeStart();
        }

        void onPopScope()
        {
            const topid = scopeStack.top.id;
            if (topid.kind == Ident.Kind.aadata && topid.get!AAData == AAData.key)
                printIdentSep();
            else
                needSeparator = true;

            putScopeEnd();
            if (scopeStack.length == 1)
            {
                output.endOfBlock();
                reset();
            }
        }
    }

    void reset()
    {
        needSeparator = false;
        assert (enumMemberDef.isNull);
        assert (needIdentStack.empty);
    }
    
public:

    this(TextOutput o, IdTranslator tr, ValueFormatter vf)
    {
        output = enforce(o, "output is null");
        idtr = tr.or(new IdNoTranslator);
        vfmt = vf.or(new SimpleValueFormatter);
        idTmpOutput = new AppenderOutputRef;
        needIdentStack = new BaseStack!bool;
    }

override:

    void putValue(in Value v)
    {
        if (needSeparator) printValueSep();

        if (enumMemberDef.isNull)
            vfmt.formatValue(output, scopeStack, v);
        else
        {
            auto x = enumMemberDef.get[v.get!uint].name;
            vfmt.formatValue(output, scopeStack, Value(x));
        }
    }
}

unittest
{
    auto ao = new AppenderOutput;

    auto tds = new ExampleTextDataSink(ao, null, null);

    auto brds = new BaseRootDataSink(tds);

    static struct Foo
    {
        int first;
        string second;
    }

    brds.putData(Foo(10, "hello"));
    import std.stdio;
    //stderr.writeln(ao.buffer[]);
    assert (ao.buffer[] == "{ first: 10, second: hello }");
    ao.clear();

    brds.putData(Foo(42, "world"));
    assert (ao.buffer[] == "{ first: 42, second: world }");
    ao.clear();

    static struct Bar
    {
        ubyte[][] bytes;
        string name;
        Foo[] foos;
    }

    enum TEnum
    {
        one = "ONE",
        two = "TWO"
    }

    static struct Baz
    {
        Bar[] bars;
        int[string] zz;
        TEnum tenum;
    }

    brds.putData(Baz(
        [
            Bar([[1],[1,2],[3]], "N1", [Foo(10, "hello"), Foo(42, "world")]),
            Bar([[6,5],[5],[6]], "21", [Foo(33, "bravo"), Foo(77, "zzzzz")]),
        ],
        [ "asdf": 1024 ],
        TEnum.one
    ));
    enum expect1 = "{ "~
            "bars: [ "~
                "{ "~
                    "bytes: [ [ 1 ], [ 1, 2 ], [ 3 ] ], "~
                    "name: N1, "~
                    "foos: [ "~
                        "{ first: 10, second: hello }, "~
                        "{ first: 42, second: world } "~
                    "] "~
                "}, "~
                "{ "~
                    "bytes: [ [ 6, 5 ], [ 5 ], [ 6 ] ], "~
                    "name: 21, "~
                    "foos: [ "~
                        "{ first: 33, second: bravo }, "~
                        "{ first: 77, second: zzzzz } "~
                    "] "~
                "} "~
            "], "~ 
            "zz: { asdf: 1024 }, "~
            "tenum: one " ~
        "}";
    //stderr.writeln(ao.buffer[]);
    //stderr.writeln(expect1);
    assert (ao.buffer[] == expect1);
    ao.clear();
}
