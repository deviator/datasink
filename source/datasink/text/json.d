module datasink.text.json;

import datasink.text.base;

class JsonValueFormatter : ValueFormatter
{
const:
    void putEscapeString(TextOutputRef output, scope const(char)[] str)
    {
        put(output, '"');
        foreach (dchar c; str)
        {
            switch (c)
            {
                case 0x08: put(output, `\b`); break; // backspace
                case 0x0C: put(output, `\f`); break; // form feed
                case '\n': put(output, `\n`); break;
                case '\r': put(output, `\r`); break;
                case '\t': put(output, `\t`); break;
                case '"':  put(output, `\"`); break;
                case '\\': put(output, `\\`); break;
                default:   put(output, c);    break;
            }
        }
        put(output, '"');
    }

    void putRawBytes(TextOutputRef output, scope const(void)[] raw)
    {
        import std.base64 : Base64;
        const r = cast(ubyte[])raw;
        put(output, '"');
        put(output, Base64.encoder(r));
        put(output, '"');
    }
override:
    void formatValue(TextOutputRef output,
                     scope const(Scope[]) scopeStack,
                     string id,
                     in Value val)
    {
        FS: final switch (val.kind) with (Value.Kind)
        {
            case str:
                putEscapeString(output, val.get!string);
                break;
            case raw:
                putRawBytes(output, val.get!(const(void)[]));
                break;

            case bit:
                put(output, cast(bool)(val.get!Bool) ? "true" : "false");
                break;

            case f32:
                formattedWrite(output, "%.8f", val.get!float);
                break;
            case f64:
                formattedWrite(output, "%.15f", val.get!double);
                break;

            static foreach (i, k; [i8, u8, i16, u16, i32, u32, i64, u64])
            {
            case k:
                formattedWrite(output, "%d", val.get!k);
                break FS;
            }
        }
    }
}

class JsonDataSink : BaseTextDataSink
{
protected:

    JsonValueFormatter jvf;

    override // BaseTextDataSink
    {
        void insertSeparator() { put(output, ','); }
        void insertIdentSep() { put(output, ':'); }
        void printString(scope const(char[]) str)
        { jvf.putEscapeString(output, str); }

        void putScopeStart()
        {
            putScopeStrings("{", "[",
                { enumMemberDef = scopeStackTop.get!EnumDsc.def; });
        }

        void putScopeEnd()
        { putScopeStrings("}", "]", { enumMemberDef.nullify; }); }
    }

public:
    this(TextOutput o, IdTranslator tr, JsonValueFormatter fv)
    {
        jvf = fv.or(new JsonValueFormatter);
        super(o, tr, jvf);
    }
}

unittest
{
    auto ao = new AppenderOutput;

    auto ru = new SimpleMapIdTranslator([
        "one": "один\nраз",
        "two": "два\tраза"
    ]);

    auto jds = new JsonDataSink(ao, ru, null);

    auto brds = new BaseRootDataSink(jds);

    static struct Foo
    {
        int one;
        string two;
    }
    brds.putData(Foo(10, `hel"lo`));
    assert (ao.data[] == `{"один\nраз":10,"два\tраза":"hel\"lo"}`);
    ao.data.clear();

    static struct Bar
    {
        int one;
        ubyte[] two;
        string three;
    }
    brds.putData(Bar(10, [5,6,7], `hel,lo`));
    assert (ao.data[] == `{"один\nраз":10,"два\tраза":[5,6,7],"three":"hel,lo"}`);
    ao.data.clear();

    static struct RawHolder { const(void)[] raw; }
    const raw = cast(ubyte[])"some text";
    brds.putData(RawHolder(raw));
    assert (ao.data[] == `{"raw":"c29tZSB0ZXh0"}`);
    ao.data.clear();
}
