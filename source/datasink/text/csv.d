module datasink.text.csv;

import datasink.text.base;

import std : Appender;

class CSVValueFormatter : ValueFormatter
{
    CtrlTextBuffer valueTmp;
    CtrlTextBuffer escapeTmp;

    string newline = "\r\n";
    string idJoiner = ".";
    dchar delimiter = ',';
    dchar escape = '"';

    void putEscapeString(TextBuffer o, scope const(char[]) str)
    {
        escapeTmp.clear();
        bool e = false;

        foreach (dchar c; str)
        {
            if (c == escape)
            {
                put(escapeTmp, escape);
                put(escapeTmp, escape);
                e = true;
                continue;
            }
            else if (c == delimiter ||
                     c == ' ' ||
                     c == '\n'
                     ) e = true;

            put(escapeTmp, c);
        }
        if (e) put(o, escape);
        put(o, escapeTmp[]);
        if (e) put(o, escape);
    }

    /+  не самое красивое решение, дополнительно выглядит криво в
        конструкторе CSVDataSink, необходимо для возможности
        локализовать значения true и false
     +/
    IdTranslator idTranslator;

    this(scope CtrlTextBuffer delegate() makeBuffer)
    {
        if (makeBuffer is null)
            makeBuffer = () => new ArrayTextBuffer;
        valueTmp = makeBuffer();
        escapeTmp = makeBuffer();
    }

override:
    void formatValue(TextBuffer o, const ScopeStack ss, in Value v)
    {
        alias K = Value.Kind;

        valueTmp.clear();

        // switch-case with label don't allow declare vairable in case block
        // error like goto skip variable declaration
        // LDC - the LLVM D compiler (1.22.0)
        if (v.kind == K.bit)
        {
            const bv = cast(bool)v.get!Bool;
            if (idTranslator !is null)
                idTranslator.translateId(valueTmp, ss, Ident(bv ? "true" : "false"));
            else formattedWrite(valueTmp, "%s", bv);
        }
        else
        static foreach (kind; EnumMembers!K)
        {
            static if (kind != K.bit) // special case above
                if (v.kind == kind)
                    formattedWrite(valueTmp, "%s", v.get!kind);
        }
        putEscapeString(o, valueTmp[]);
    }
}

class CSVDataSink : BaseTextDataSink
{
protected:
    IdTranslator idtr;
    CSVValueFormatter vfmt;

    CtrlTextBuffer lastHeader;
    CtrlTextBuffer headerBuffer;
    CtrlTextBuffer dataBuffer;
    CtrlTextBuffer printIdentTmp;

    bool needSeparator;

    void printValueSep()
    {
        put(headerBuffer, vfmt.delimiter);
        put(dataBuffer, vfmt.delimiter);
    }

    void printIdent()
    {
        printIdentTmp.clear();

        void print(ref const(Ident) id)
        {
            idtr.translateId(printIdentTmp, scopeStack, id);
        }

        if (scopeStack.length >= 1)
            print(scopeStack[][1].id);

        if (scopeStack.length > 1)
            foreach (i, s; scopeStack[][2..$])
            {
                put(printIdentTmp, vfmt.idJoiner);
                print(s.id);
            }

        vfmt.putEscapeString(headerBuffer, printIdentTmp[]);
    }

    override // BasetDataSink
    {
        void onPushScope() { }

        void onPopScope() { }

        void onScopeEmpty()
        {
            temp.clear();

            if (lastHeader[] != headerBuffer[])
            {
                lastHeader.clear();
                put(lastHeader, headerBuffer[]);

                put(temp, headerBuffer[]);
                put(temp, vfmt.newline);
            }
            headerBuffer.clear();

            put(temp, dataBuffer[]);
            put(temp, vfmt.newline);

            dataBuffer.clear();

            super.onScopeEmpty();
        }

        void reset()
        {
            needSeparator = false;
        }
    }

public:
    this(TextSink ts, IdTranslator tr, CSVValueFormatter fmt)
    {
        super(ts);

        lastHeader    = makeCtrlTextBuffer();
        headerBuffer  = makeCtrlTextBuffer();
        dataBuffer    = makeCtrlTextBuffer();
        printIdentTmp = makeCtrlTextBuffer();

        idtr = tr.or(new IdNoTranslator);
        vfmt = fmt.or(new CSVValueFormatter(&makeCtrlTextBuffer));
        vfmt.idTranslator = idtr;
    }

    void resetHeader() { lastHeader.clear(); }

override:

    void putLength(ulong l) { }

    void putValue(in Value v)
    {
        if (needSeparator) printValueSep();
        printIdent();
        vfmt.formatValue(dataBuffer, scopeStack, v);
        needSeparator = true;
    }
}

unittest
{
    auto ts = new ArrayTextSink;

    auto ru = new SimpleMapIdTranslator([
        "one": "один раз",
        "two": "два,раза",
        "three": "три",
        "true": "да",
        "false": "нет"
    ]);

    auto fmt = new CSVValueFormatter(null);
    fmt.idJoiner = "->";

    auto ds = new CSVDataSink(ts, ru, fmt);

    auto brds = new BaseRootDataSink(ds);

    static struct Foo
    {
        int one;
        string two;
    }

    brds.putData(Foo(10, "hello"));

    import std : stderr;

    assert (ts[] == `"один раз","два,раза"`~"\r\n10,hello\r\n" );

    brds.putData(Foo(5, "okda"));

    assert (ts[] == `"один раз","два,раза"`~"\r\n" ~
                    "10,hello\r\n" ~
                    "5,okda\r\n");

    static struct Bar { int one; }
    brds.putData(Bar(42));
    assert (ts[] == `"один раз","два,раза"`~"\r\n" ~
                    "10,hello\r\n" ~
                    "5,okda\r\n" ~ 
                    `"один раз"`~"\r\n" ~
                    "42\r\n");

    static struct Foo1
    {
        bool first;
        bool one;
    }
    brds.putData(Foo1(true, false));

    assert (ts[] == `"один раз","два,раза"`~"\r\n" ~
                    "10,hello\r\n" ~
                    "5,okda\r\n" ~ 
                    `"один раз"`~"\r\n" ~
                    "42\r\n" ~
                    `first,"один раз"`~"\r\n" ~
                    "да,нет\r\n");

    ts.clear();

    static struct Baz
    {
        static struct X
        {
            bool one;
            static struct Two
            {
                int ok;
            }
            Two two;
        }
        X x;
    }

    brds.putData(Baz(Baz.X(true, Baz.X.Two(10))));

    assert (ts[] == `"x->один раз","x->два,раза->ok"`~"\r\n" ~
                    "да,10\r\n");
}
