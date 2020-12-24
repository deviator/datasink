module datasink.util;

import std.exception : enforce;

interface ValueSrc(T) { T get() const; }

interface ValueDst(T) { void set(T); }

class BaseValue(T) : ValueSrc!T, ValueDst!T
{
    T value;
    override void set(T v) { value = v; }
    override T get() const { return value; }
}

struct ScopeGuard
{
    void delegate() end;
    @disable this();
    @disable this(this);
    this(void delegate() e) { end = enforce(e, "null delegate"); }
    ~this() { end(); }
}

interface Stack(T)
{
    void push(T v);
    void pop();

const @property:
    scope const(T[]) opIndex();
    bool empty();
final:
    size_t length() { return opIndex().length; }
    ref const(T) top()
    {
        assert (!empty, "stack is empty");
        return this[][$-1];
    }
}

class BaseStack(T) : Stack!T
{
    T[] data;
    ptrdiff_t cur;

    this(size_t reserve=64) { data.length = reserve; }

override:

    void push(T v)
    {
        data[cur++] = v;
        if (cur == data.length)
            data.length *= 2;
    }

    void pop()
    {
        assert (cur, "stack is empty");
        cur--;
    }

const @property:
    bool empty() { return cur == 0; }
    scope const(T[]) opIndex() { return data[0..cur]; }
}

/++
    use:
    some = a.or(new Some);
 +/
auto or(A,B)(A a, B b) { return a !is null ? a : b; }


unittest
{
    auto bs = new BaseStack!uint(128);

    import core.memory : GC;

    bool noAllocs(in GC.Stats f, in GC.Stats s)
    { return (s.usedSize - f.usedSize) == 0; }

    const stats = GC.stats;
    foreach (i; 0 .. 100) bs.push(i);
    assert (noAllocs(stats, GC.stats));
    foreach_reverse (i; 0 .. 100)
    {
        assert (bs.top == i);
        bs.pop();
    }
    foreach (i; 0 .. 100) bs.push(i);
    assert (noAllocs(stats, GC.stats));
    foreach_reverse (i; 0 .. 100)
    {
        assert (bs.top == i);
        bs.pop();
    }
    assert (noAllocs(stats, GC.stats));
}
