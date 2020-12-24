module datasink.text.output;

import std : OutputRange, Appender;

public import std : formattedWrite, put;

///
interface TextBuffer:
    OutputRange!char,
    OutputRange!(const(char[]))
{
    void put(char c);
    void put(const(char[]) c);
}

///
interface CtrlTextBuffer : TextBuffer
{
    void clear();
    scope const(char)[] opIndex() const;
}

///
class ArrayTextBuffer : CtrlTextBuffer
{
    char[] buffer;
    size_t cur;
    this(size_t reserve=32) { buffer.length = reserve > 4 ? reserve : 4; }
override:
    void clear() { cur = 0; }
    scope const(char)[] opIndex() const { return buffer[0..cur]; }
    void put(char c)
    {
        buffer[cur++] = c;
        if (cur == buffer.length) buffer.length *= 2;
    }
    void put(const(char[]) c)
    {
        const ne = cur + c.length;
        while (ne >= buffer.length) buffer.length *= 2;
        buffer[cur..ne] = c[]; // equal by speed with memcpy
        cur = ne;
    }
}

/// for full builded text output by one call
interface TextSink { void sink(scope const(char)[]); }

class ArrayTextSink : TextSink
{
    import std.algorithm : max;
    ArrayTextBuffer buffer;
    this() { buffer = new ArrayTextBuffer(512); }
    void reserve(size_t cap) { buffer.buffer.length = max(buffer.buffer.length, cap); }
    scope const(char)[] opIndex() const { return buffer[]; }
    void clear() { buffer.clear(); }
    override void sink(scope const(char)[] s) { buffer.put(s); }
}

class NullTextSink : TextSink
{
    override void sink(scope const(char)[] s) { }
}
