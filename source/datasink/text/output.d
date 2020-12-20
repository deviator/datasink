module datasink.text.output;

import std : OutputRange, Appender;

public import std : formattedWrite, put;

alias TextOutput = OutputRange!char;

class AppenderOutput : TextOutput
{
    Appender!(char[]) buffer;
    alias buffer this;
override:
    void put(char c) { buffer.put(c); }
}
