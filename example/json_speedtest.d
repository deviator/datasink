/+ dub.sdl:
    dependency "datasink" path=".."
    dependency "vibe-d:data" version="0.9.3-beta.1"
    dependency "asdf" version="0.7.5"
 +/

import core.memory : GC;
import std.stdio;
import std.datetime;
import std.array : Appender;

import datasink;
import datasink.text.output;
import datasink.text.json;

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
        Bar([[1],[1],[2],[3]], "N0", [Foo(10, "при\"е\nт"), Foo(42, "ми\\р")]),
        Bar([[1],[1],[2],[3]], "N1", [Foo(10, "\nп\tр\"е\nт"), Foo(42, "\nм\tи\\р\"")]),
        Bar([[1],[1],[2],[3]], "N2", [Foo(10, "при\"е\nт"), Foo(42, "ми\\р")]),
        Bar([[1],[1],[2],[3]], "N3", [Foo(10, "\nп\tр\"е\nт"), Foo(42, "\nм\tи\\р\"")]),
        Bar([[1],[1],[2],[3]], "N4", [Foo(10, "при\"е\nт"), Foo(42, "ми\\р")]),
        Bar([[1],[1],[2],[3]], "N5", [Foo(10, "\nп\tр\"е\nт"), Foo(42, "\nм\tи\\р\"")]),
        Bar([[1],[1],[2],[3]], "N6", [Foo(10, "при\"е\nт"), Foo(42, "ми\\р")]),
        Bar([[1],[1],[2],[3]], "N7", [Foo(10, "\nп\tр\"е\nт"), Foo(42, "\nм\tи\\р\"")]),
        Bar([[1],[1],[2],[3]], "N8", [Foo(10, "при\"е\nт"), Foo(42, "ми\\р")]),
        Bar([[1],[1],[2],[3]], "N9", [Foo(10, "\nп\tр\"е\nт"), Foo(42, "\nм\tи\\р\"")]),
    ],
    [ "a\"s\nd\tf": 1024, "привет мир": 64, "": 32 ],
    TEnum.one
);

enum N = 100;
enum K = 3;

enum Y = "\033[33m";
enum G = "\033[32m";
enum R = "\033[31m";
enum X = "\033[0m";

void fnc1()
{
    auto bzz = baz1;

    auto tts = new ArrayTextSink;
    auto jds = new JsonDataSink(tts);
    auto brds = new BaseRootDataSink(jds);

    Duration test()
    {
        Duration d;
        foreach (i; 0 .. N)
        {
            const start = Clock.currTime;
            brds.putData(bzz);
            d += Clock.currTime - start;
            tts.clear();
        }
        return d / N;
    }

    test(); // allocate buffers

    foreach (i; 0 .. K)
    {
        const stats = GC.stats;
        auto tm = test();
        const diff = cast(ptrdiff_t)GC.stats.usedSize - cast(ptrdiff_t)stats.usedSize;
        writeln(tm);
        assert (diff == 0, "memory allocate at equal repeat put");
    }
}

void fnc2()
{
    import vibe.data.json;

    auto bzz = baz1;

    auto tts = new ArrayTextSink;
    auto buf0 = new ArrayTextBuffer;
    Duration test()
    {
        Duration d;
        foreach (i; 0 .. N)
        {
            const start = Clock.currTime;
            serializeToJson(buf0, bzz);
            tts.sink(buf0[]);
            d += Clock.currTime - start;
            buf0.clear();
            tts.clear();
        }
        return d / N;
    }
    test();

    writeln("vibe.data.json");

    foreach (i; 0 .. K)
    {
        const stats = GC.stats;
        auto tm = test();
        const diff = cast(ptrdiff_t)GC.stats.usedSize - cast(ptrdiff_t)stats.usedSize;
        write(tm);
        writeln(" | memdiff: ", diff > 0 ? R : diff < 0 ? Y : G, diff, X, " ( ",
                stats.usedSize, " -> ", GC.stats.usedSize, " )");
    }
}

void fnc3()
{
    import asdf;

    auto bzz = baz1;

    auto tts = new ArrayTextSink;
    Duration test()
    {
        Duration d;
        foreach (i; 0 .. N)
        {
            const start = Clock.currTime;
            tts.sink(serializeToJson(bzz));
            d += Clock.currTime - start;
            tts.clear();
        }
        return d / N;
    }
    test();

    writeln("asdf");

    foreach (i; 0 .. K)
    {
        const stats = GC.stats;
        auto tm = test();
        const diff = cast(ptrdiff_t)GC.stats.usedSize - cast(ptrdiff_t)stats.usedSize;
        write(tm);
        writeln(" | memdiff: ", diff > 0 ? R : diff < 0 ? Y : G, diff, X, " ( ",
                stats.usedSize, " -> ", GC.stats.usedSize, " )");
    }
}

void main()
{
    fnc1();
    fnc2();
    fnc3();
}
