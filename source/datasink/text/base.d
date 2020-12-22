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
    TextSink textSink;
    CtrlTextBuffer temp;

    override void onScopeEmpty()
    {
        textSink.sink(temp[]);
        temp.clear();
        reset();
    }

    abstract void reset();

    CtrlTextBuffer makeCtrlTextBuffer()
    {
        return new ArrayTextBuffer;
    }

public:
    this(TextSink ts)
    {
        textSink = enforce(ts, "text sink is null");
        temp = makeCtrlTextBuffer();
    }
}

class ExampleTextDataSink : BaseTextDataSink
{
protected:
    IdTranslator idtr;
    ValueFormatter vfmt;

    bool needSeparator = false;

    bool needIdent() const @property
    {
        if (needIdentStack.empty) return false;
        return needIdentStack.top;
    }
    Stack!bool needIdentStack;

    CtrlTextBuffer idTmpOutput;

    void printValueSep() { put(temp, ", "); }
    void printIdentSep() { put(temp, ": "); }
    void printString(scope const(char[]) str) { put(temp, str); }

    void printIdent(Ident id)
    {
        idTmpOutput.clear();
        idtr.translateId(idTmpOutput, scopeStack, id);
        printString(idTmpOutput[]);
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
                put(temp, obj);
                onStartPushNeedIdent(true);
                break;
            case aArray:
                put(temp, obj);
                onStartPushNeedIdent(false);
                break;
            case sArray: case dArray: case tuple:
                put(temp, arr);
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
        }

        void reset()
        {
            needSeparator = false;
            assert (enumMemberDef.isNull);
            assert (needIdentStack.empty);
        }
    }
    
public:

    this(TextSink ts, IdTranslator tr, ValueFormatter vf)
    {
        super(ts);

        idtr = tr.or(new IdNoTranslator);
        vfmt = vf.or(new SimpleValueFormatter);

        idTmpOutput = makeCtrlTextBuffer();
        needIdentStack = new BaseStack!bool;
    }

override:

    void putValue(in Value v)
    {
        if (needSeparator) printValueSep();

        if (enumMemberDef.isNull)
            vfmt.formatValue(temp, scopeStack, v);
        else
        {
            auto x = enumMemberDef.get[v.get!uint].name;
            vfmt.formatValue(temp, scopeStack, Value(x));
        }
    }
}

unittest
{
    auto ts = new ArrayTextSink;

    auto tds = new ExampleTextDataSink(ts, null, null);

    auto brds = new BaseRootDataSink(tds);

    static struct Foo
    {
        int first;
        string second;
    }

    brds.putData(Foo(10, "hello"));
    import std.stdio;
    //stderr.writeln(ts[]);
    assert (ts[] == "{ first: 10, second: hello }");
    ts.clear();

    brds.putData(Foo(42, "world"));
    assert (ts[] == "{ first: 42, second: world }");
    ts.clear();

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
    //stderr.writeln(ts[]);
    //stderr.writeln(expect1);
    assert (ts[] == expect1);
    ts.clear();
}
