/+ dub.sdl:
    dependency "datasink" path=".."
    dependency "sbin" version="~>0.7.1"
 +/

import std.exception : enforce;
import std.stdio;

import sbin;
import datasink;

alias Msg = TaggedVariant!(
    ["popScope",   "pushScope", "value"],
      int,         Scope,       Value
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
    void putValue(in Value v) { addMsg(Msg(v)); }
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
                (Value v) { rds.putValue(v); }
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
    }

    auto bars = [
        Bar([[1],[1,2],[3]], "N1", [Foo(10, "hello"), Foo(42, "world")]),
        Bar([[2],[4,6],[8]], "N2", [Foo(12, "alpha"), Foo(40, "betta")]),
        Bar([[3],[5,7],[9]], "N3", [Foo(14, "текст"), Foo(38, "слова")]),
    ];

    foreach (bar; bars)
    {
        enforce (data.length == 0);
        snd.putData(bar);
        enforce (data.length != 0);

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
            auto _ = snd.scopeGuard(Scope(TypeDsc(ObjectDsc("X"))));
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
