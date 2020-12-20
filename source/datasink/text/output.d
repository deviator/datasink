module datasink.text.output;

import std : OutputRange, Appender;

public import std : formattedWrite, put;

///
alias TextBuffer = OutputRange!char;

///
interface CtrlTextBuffer : TextBuffer
{
    void clear();
    scope const(char)[] opIndex() const;
}

///
class AppenderBuffer : CtrlTextBuffer
{
    Appender!(char[]) buffer;
override:
    void clear() { buffer.clear(); }
    scope const(char)[] opIndex() const { return buffer[]; }
    void put(char c) { buffer.put(c); }
}

/// for full builded text output by one call
interface TextSink { void sink(scope const(char)[]); }

version (unittest)
{
    class TestTextSink : TextSink
    {
        string str;
        string opIndex() const { return str; }
        void clear() { str.length = 0; }
        override void sink(scope const(char)[] ch) { str ~= ch.idup; }
    }
}
