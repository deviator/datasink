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
    bool empty();
    size_t length();
    ref const(T) top();
    const(T[]) data();
}

class BaseStack(T) : Stack!T
{
    T[] _data;

    this(size_t reserve=64) { _data.reserve = reserve; }

override:

    void push(T v) { _data ~= v; }

    void pop()
    {
        assert (!empty, "stack is empty");
        _data.length--;
    }

const @property:
    bool empty() { return _data.length == 0; }
    size_t length() { return _data.length; }
    ref const(T) top() { return _data[$-1]; }
    const(T[]) data() { return _data; }
}

/++
    use:
    some = a.or(new Some);
 +/
auto or(A,B)(A a, B b) { return a !is null ? a : b; }
