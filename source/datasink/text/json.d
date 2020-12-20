module datasink.text.json;

import datasink.text.base;

class JsonValueFormatter : ValueFormatter
{
const:
    void putEscapeString(TextBuffer o, scope const(char)[] str)
    {
        put(o, '"');
        foreach (dchar c; str)
        {
            switch (c)
            {
                case 0x08: put(o, `\b`); break; // backspace
                case 0x0C: put(o, `\f`); break; // form feed
                case '\n': put(o, `\n`); break;
                case '\r': put(o, `\r`); break;
                case '\t': put(o, `\t`); break;
                case '"':  put(o, `\"`); break;
                case '\\': put(o, `\\`); break;
                default:   put(o, c);    break;
            }
        }
        put(o, '"');
    }

    void putRawBytes(TextBuffer o, scope const(void)[] raw)
    {
        import std.base64 : Base64;
        const r = cast(ubyte[])raw;
        put(o, '"');
        put(o, Base64.encoder(r));
        put(o, '"');
    }

override:
    void formatValue(TextBuffer o, const ScopeStack ss, in Value val)
    {
        FS: final switch (val.kind) with (Value.Kind)
        {
            case str:
                putEscapeString(o, val.get!string);
                break;
            case raw:
                putRawBytes(o, val.get!(const(void)[]));
                break;

            case bit:
                put(o, cast(bool)(val.get!Bool) ? "true" : "false");
                break;

            case f32: case f64:
                formattedWrite(o, "%e", val.get!double);
                break;

            static foreach (i, k; [i8, u8, i16, u16, i32, u32, i64, u64])
            {
            case k:
                formattedWrite(o, "%d", val.get!k);
                break FS;
            }
        }
    }
}

class JsonDataSink : BaseTextDataSink
{
protected:
    bool pretty;
    size_t offset;
    string offsetStr = "  ";

    bool needSeparator = false;

    bool needIdent() const @property
    {
        if (needIdentStack.empty) return false;
        return needIdentStack.top;
    }
    Stack!bool needIdentStack;

    CtrlTextBuffer idTmpOutput;
    IdTranslator idtr;
    JsonValueFormatter vfmt;

    void printNewLine() { put(temp, '\n'); printOffset(); }
    void printSpace() { put(temp, ' '); }
    void printOffset()
    {
        import std : repeat, take;
        put(temp, offsetStr.repeat.take(offset));
    }

    void printValueSep()
    {
        put(temp, ',');
        if (pretty) printNewLine();
    }

    void printIdentSep()
    {
        put(temp, ':');
        if (pretty) printSpace();
    }

    void printString(scope const(char[]) str)
    { vfmt.putEscapeString(temp, str); }

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

    void putScope(bool start)
    {
        const top = scopeStack.top;

        void needIdentManip(bool n)
        {
            if (start) needIdentStack.push(n);
            else needIdentStack.pop();
        }

        static immutable string[2] obj = ["{", "}"];
        static immutable string[2] arr = ["[", "]"];

        void scopeBrackets(string[2] br)
        {
            if (start)
            {
                put(temp, br[0]);
                if (pretty)
                {
                    offset++;
                    printNewLine();
                }
            }
            else
            {
                if (pretty)
                {
                    offset--;
                    printNewLine();
                }
                put(temp, br[1]);
            }
        }

        final switch (top.dsc.kind) with(top.dsc.Kind)
        {
            case value: break;
            case object: case tUnion:
                scopeBrackets(obj);
                needIdentManip(true);
                break;
            case aArray:
                scopeBrackets(obj);
                needIdentManip(false);
                break;
            case sArray: case dArray: case tuple:
                scopeBrackets(arr);
                needIdentManip(false);
                break;
            case enumEl:
                if (!start) enumMemberDef.nullify; 
                else enumMemberDef = scopeStack.top.dsc.get!EnumDsc.def;
                break;
        }
    }

    override // BaseDataSink
    {
        void onPushScope()
        {
            if (needSeparator) printValueSep();
            needSeparator = false;
            if (needIdent) printIdent(scopeStack.top.id);
            putScope(true);
        }

        void onPopScope()
        {
            const topid = scopeStack.top.id;
            if (topid.kind == Ident.Kind.aadata && topid.get!AAData == AAData.key)
                printIdentSep();
            else
                needSeparator = true;

            putScope(false);
        }

        void reset()
        {
            needSeparator = false;
            assert (enumMemberDef.isNull);
            assert (needIdentStack.empty);
        }
    }
    
public:

    this(TextSink ts, IdTranslator tr, JsonValueFormatter vf, bool pretty)
    {
        super(ts);
        idtr = tr.or(new IdNoTranslator);
        vfmt = vf.or(new JsonValueFormatter);

        idTmpOutput = makeCtrlTextBuffer();
        needIdentStack = new BaseStack!bool;

        this.pretty = pretty;
    }

    this(TextSink ts, bool pretty=false) { this(ts, null, null, pretty); }

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
    auto ts = new TestTextSink;

    auto ru = new SimpleMapIdTranslator([
        "one": "один\nраз",
        "two": "два\tраза"
    ]);

    auto jds = new JsonDataSink(ts, ru, null, false);

    auto brds = new BaseRootDataSink(jds);

    static struct Foo
    {
        int one;
        string two;
    }
    brds.putData(Foo(10, `hel"lo`));
    assert (ts[] == `{"один\nраз":10,"два\tраза":"hel\"lo"}`);
    ts.clear();

    static struct Bar
    {
        int one;
        ubyte[] two;
        string three;
    }
    brds.putData(Bar(10, [5,6,7], `hel,lo`));
    assert (ts[] == `{"один\nраз":10,"два\tраза":[5,6,7],"three":"hel,lo"}`);
    ts.clear();

    static struct RawHolder { const(void)[] raw; }
    const raw = cast(ubyte[])"some text";
    brds.putData(RawHolder(raw));
    assert (ts[] == `{"raw":"c29tZSB0ZXh0"}`);
    ts.clear();
}

unittest
{
    auto ts = new TestTextSink;

    auto jds = new JsonDataSink(ts, true);

    auto brds = new BaseRootDataSink(jds);

    import std.stdio;

    static struct Foo
    {
        int first;
        string second;
    }

    brds.putData(Foo(10, "hello"));
    assert (ts[] == "{\n  \"first\": 10,\n  \"second\": \"hello\"\n}");
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

    enum expect1 = 
        "{\n  \"bars\": [\n"~
        "    {\n      \"bytes\": [\n"~
        "        [\n          1\n        ],\n"~
        "        [\n          1,\n          2\n        ],\n"~
        "        [\n          3\n        ]\n      ],\n"~
        "      \"name\": \"N1\",\n"~
        "      \"foos\": [\n"~
        "        {\n          \"first\": 10,\n          \"second\": \"hello\"\n        },\n"~
        "        {\n          \"first\": 42,\n          \"second\": \"world\"\n        }\n"~
        "      ]\n    },\n"~
        "    {\n      \"bytes\": [\n"~
        "        [\n          6,\n          5\n        ],\n"~
        "        [\n          5\n        ],\n"~
        "        [\n          6\n        ]\n      ],\n"~
        "      \"name\": \"21\",\n"~
        "      \"foos\": [\n"~
        "        {\n          \"first\": 33,\n          \"second\": \"bravo\"\n        },\n"~
        "        {\n          \"first\": 77,\n          \"second\": \"zzzzz\"\n        }\n"~
        "      ]\n    }\n  ],\n"~
        "  \"zz\": {\n    \"asdf\": 1024\n  },\n"~
        "  \"tenum\": \"one\"\n}";
    assert(ts[] == expect1);
}
