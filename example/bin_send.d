/+ dub.sdl:
    dependency "datasink" path=".."
    dependency "sbin" version="~>0.7.1"
 +/

import std.exception : enforce;
import std.stdio;

import sbin;
import datasink;

alias Length = ulong;

struct EnumVal
{
    EnumDsc dsc;
    ulong index;
}

struct KindVal
{
    EnumDsc dsc;
    ulong index;
}

alias Msg = TaggedVariant!(
    ["popScope",   "pushScope", "value", "length", "enumVal", "kindVal"],
      int,          Scope,       Value,   Length,   EnumVal,   KindVal
);

class BinSenderRDS : RootDataSink
{
protected:
    Msg[] buffer;
    size_t ptr;

    void addMsg(Msg m)
    {
        buffer[ptr++] = m;
        if (ptr == buffer.length)
            buffer.length *= 2;
    }

    void resetBuffer() { ptr = 0; }

    void sendBuffer() { sink(sbinSerialize(buffer[0..ptr])); }

    int scopeCounter;

    Sink sink;

public:

    alias Sink = void delegate(scope const(void)[]);

    this(Sink sink)
    {
        buffer.length = 32;
        this.sink = enforce(sink, "sink is null");
    }

override:
    void pushScope(Scope s)
    {
        addMsg(Msg(s));
        scopeCounter++;
    }
    void popScope()
    {
        scopeCounter--;
        addMsg(Msg(scopeCounter));
        if (scopeCounter == 0)
        {
            sendBuffer();
            resetBuffer();
        }
    }
    void putLength(ulong l) { addMsg(Msg(Length(l))); }
    void putValue(in Value v) { addMsg(Msg(v)); }
    void putEnum(in EnumDsc dsc, ulong i) { addMsg(Msg(EnumVal(EnumDsc(dsc.members.dup), i))); }
    void putKind(in EnumDsc dsc, ulong i) { addMsg(Msg(KindVal(EnumDsc(dsc.members.dup), i))); }
}

class BinReader
{
    RootDataSink rds;

    this(RootDataSink rds) { this.rds = rds; }

    Msg[] buffer;

    void read(scope const(void)[] data)
    {
        sbinDeserialize(cast(const(ubyte)[])data, buffer);
        foreach (msg; buffer)
            msg.visit!(
                (int)     { rds.popScope(); },
                (Scope s) { rds.pushScope(s); },
                (Value v) { rds.putValue(v); },
                (Length l) { rds.putLength(l); },
                (EnumVal v) { rds.putEnum(v.dsc, v.index); },
                (KindVal v) { rds.putKind(v.dsc, v.index); },
            );
    }
}

void main()
{
    void[] data;
    void sink(scope const(void)[] d) { data = d.dup; }
    auto snd = new BinSenderRDS(&sink);

    auto ts1 = new ArrayTextSink;
    auto ts2 = new ArrayTextSink;
    auto ds1 = new JsonDataSink(ts1, false);
    auto ds2 = new CSVDataSink(ts2, null, null);
    auto dsl = new ListDataSink([ds1, ds2]);
    auto rdr = new BinReader(new BaseRootDataSink(dsl));

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
        string[string] aa;
    }

    auto bars = [
        Bar([[1],[1,2],[3]], "N1", [Foo(10, "hel\nlo"), Foo(42, "world")], ["ok":"da", "12":"21"]),
        Bar([[2],[4,6],[8]], "N2", [Foo(12, "alpha"), Foo(40, "betta")], ["no":"ad", "13":"31"]),
        Bar([[3],[5,7],[9]], "N3", [Foo(14, "текст"), Foo(38, "слова")], ["00":"11", "32":"23"]),
    ];

    foreach (bar; bars)
    {
        enforce (data.length == 0);
        snd.putData(bar);
        enforce (data.length != 0);
        writeln("data: ", data.length);
        writeln("sbin: ", sbinSerialize(bar).length);

        rdr.read(data);
        data = [];
        writeln(ts1[]);
        ts1.clear();
    }

    writeln();
    writeln(ts2[]);
    ts2.clear();
    writeln();

    import datasink.typedesc;
    import std.datetime : Clock;

    writeln("rt structure");
    foreach (i; 0 .. 3)
    {
        // send not exist type
        {
            auto _ = snd.scopeGuard(Scope(TypeDsc(ObjectDsc.init)));
            snd.setTmpIdent(Ident("ts"));
            snd.putData(Clock.currStdTime);

            snd.setTmpIdent(Ident("bar"));
            snd.putData(bars[i]);
        }

        rdr.read(data);
        writeln(ts1[]);
        ts1.clear();
    }

    writeln();
    writeln(ts2[]);
}
