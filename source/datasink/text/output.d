module datasink.text.output;

import std : OutputRange, Appender;

public import std : formattedWrite, put;

alias TextOutputRef = OutputRange!char;

interface TextOutput : TextOutputRef
{
    void endOfBlock();
}

class AppenderOutputRef : TextOutputRef
{
    Appender!(char[]) buffer;
    alias buffer this;
override:
    void put(char c) { buffer.put(c); }
}

class AppenderOutput : AppenderOutputRef, TextOutput
{
override:
    void endOfBlock() {}
}
