module datasink.text.json;

import datasink.text.base;

class JsonValueFormatter : ValueFormatter
{
const:
    void putEscapeString(TextBuffer o, scope const(char)[] str)
    {
        put(o, '"');
        size_t s = 0;
        foreach (i, dchar c; str)
        {
            switch (c)
            {
                case 0x08: o.put(str[s..i]); o.put(`\b`); s=i+1; break; // backspace
                case 0x0C: o.put(str[s..i]); o.put(`\f`); s=i+1; break; // form feed
                case '\n': o.put(str[s..i]); o.put(`\n`); s=i+1; break;
                case '\r': o.put(str[s..i]); o.put(`\r`); s=i+1; break;
                case '\t': o.put(str[s..i]); o.put(`\t`); s=i+1; break;
                case '"':  o.put(str[s..i]); o.put(`\"`); s=i+1; break;
                case '\\': o.put(str[s..i]); o.put(`\\`); s=i+1; break;
                default: break;
            }
        }
        if (s < str.length) o.put(str[s..$]);
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
            case nil:
                o.put("null");
                break;

            case str:
                putEscapeString(o, val.get!string);
                break;
            case raw:
                putRawBytes(o, val.get!(const(void)[]));
                break;

            case bit:
                o.put(cast(bool)(val.get!Bool) ? "true" : "false");
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
        temp.put(',');
        if (pretty) printNewLine();
    }

    void printIdentSep()
    {
        temp.put(':');
        if (pretty) printSpace();
    }

    void printString(scope const(char[]) str)
    { vfmt.putEscapeString(temp, str); }

    void printIdent(Ident id)
    {
        if (idtr !is null)
        {
            idTmpOutput.clear();
            idtr.translateId(idTmpOutput, scopeStack, id);
            printString(idTmpOutput[]);
        }
        else printString(id.get!string);
        printIdentSep();
    }

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
                temp.put(br[0]);
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
                temp.put(br[1]);
            }
        }

        final switch (top.dsc.kind) with(top.dsc.Kind)
        {
            case value: case enumEl: break;
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

            if (topid.kind == Ident.Kind.aaKey)
                printIdentSep();
            else
                needSeparator = true;

            putScope(false);
        }

        void reset()
        {
            needSeparator = false;
            assert (needIdentStack.empty);
        }
    }
    
public:

    this(TextSink ts, IdTranslator tr, JsonValueFormatter vf, bool pretty)
    {
        super(ts);
        idtr = tr; // tr.or(new IdNoTranslator);
        vfmt = vf.or(new JsonValueFormatter);

        idTmpOutput = makeCtrlTextBuffer();

        needIdentStack = new BaseStack!bool;

        this.pretty = pretty;
    }

    this(TextSink ts, bool pretty=false) { this(ts, null, null, pretty); }

override:

    void putLength(ulong l) { }

    void putValue(in Value v)
    {
        if (needSeparator) printValueSep();
        vfmt.formatValue(temp, scopeStack, v);
    }
}

unittest
{
    auto ts = new ArrayTextSink;

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

    brds.putData(Foo(10, ``));
    assert (ts[] == `{"один\nраз":10,"два\tраза":""}`);
    ts.clear();

    brds.putData(Foo(10, `""`));
    assert (ts[] == `{"один\nраз":10,"два\tраза":"\"\""}`);
    ts.clear();

    brds.putData(Foo(10, `"привет"`));
    assert (ts[] == `{"один\nраз":10,"два\tраза":"\"привет\""}`);
    ts.clear();

    brds.putData(Foo(10, `привет"`));
    assert (ts[] == `{"один\nраз":10,"два\tраза":"привет\""}`);
    ts.clear();

    brds.putData(Foo(10, "\n\tё\n\tж\n"));
    assert (ts[] == `{"один\nраз":10,"два\tраза":"\n\tё\n\tж\n"}`);
    ts.clear();

    brds.putData(Foo(10, "ё\n\tж\n"));
    assert (ts[] == `{"один\nраз":10,"два\tраза":"ё\n\tж\n"}`);
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

version (unittest)
{
    struct Foo
    {
        int first;
        string second;
    }

    struct Bar
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

    struct Baz
    {
        Bar[] bars;
        int[string] zz;
        TEnum tenum;
    }

    enum baz1 = Baz(
        [
            Bar([[1],[1,2],[3]], "N1", [Foo(10, "hello"), Foo(42, "world")]),
            Bar([[6,5],[5],[6]], "21", [Foo(33, "bravo"), Foo(77, "zzzzz")]),
        ],
        [ "asdf": 1024 ],
        TEnum.one
    );

    enum baz1_js_pretty = 
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
        
    enum baz1_js = 
        `{"bars":[{"bytes":[[1],[1,2],[3]],"name":"N1",`~
                  `"foos":[{"first":10,"second":"hello"},`~
                          `{"first":42,"second":"world"}]},`~
                 `{"bytes":[[6,5],[5],[6]],"name":"21",`~
                  `"foos":[{"first":33,"second":"bravo"},`~
                          `{"first":77,"second":"zzzzz"}]}],`~
        `"zz":{"asdf":1024},"tenum":"one"}`;
}

unittest
{
    auto ts = new ArrayTextSink;

    auto jds = new JsonDataSink(ts, true);

    auto brds = new BaseRootDataSink(jds);

    import std.stdio;

    brds.putData(Foo(10, "hello"));
    assert (ts[] == "{\n  \"first\": 10,\n  \"second\": \"hello\"\n}");
    ts.clear();

    auto bzz = baz1;

    brds.putData(bzz);

    assert(ts[] == baz1_js_pretty);

    ts.clear();

}

unittest
{
    import core.memory : GC;
    import std.stdio;
    import std.datetime;

    auto bzz = baz1;

    auto tts = new ArrayTextSink;
    auto jds = new JsonDataSink(tts);
    auto brds = new BaseRootDataSink(jds);

    enum N = 100;

    //static immutable dsc = makeTypeDsc!Baz;

    Duration test()
    {
        Duration d;
        foreach (i; 0 .. N)
        {
            const start = Clock.currTime;

            brds.putData(bzz);

            //brds.scopeStack.push(Scope(dsc, Ident("hello")));
            //brds.scopeStack.pop();

            d += Clock.currTime - start;
            assert (tts[] == baz1_js);
            tts.clear();
        }
        return d / N;
    }

    test(); // allocate buffers

    foreach (i; 0 .. 10)
    {
        const stats = GC.stats;
        auto tm = test();
        const diff = cast(ptrdiff_t)GC.stats.usedSize - cast(ptrdiff_t)stats.usedSize;
        //writeln(tm);

        assert (diff == 0, "memory allocate at equal repeat put");

        enum Y="\033[33m";
        enum G="\033[32m";
        enum R="\033[31m";
        enum X="\033[0m";
        //writeln(diff > 0 ? R : diff < 0 ? Y : G, diff, X, " ( ",
        //        stats.usedSize, " -> ", GC.stats.usedSize, " )");
    }
}
