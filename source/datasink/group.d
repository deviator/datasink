module datasink.group;

import datasink.base;

final class NullDataSink : DataSink
{
override:
protected:
    void setScopeStack(const(ScopeStack)) { }

    void onPushScope() { }
    void onPopScope() { }
    void onScopeEmpty() { }

public:
    void putValue(in Value v) { }
}

class ListDataSink : DataSink
{
    protected DataSink[] sinks;

    this(DataSink[] list) { sinks = list; }

override:
protected:
    void setScopeStack(const(ScopeStack) ss)
    { foreach (s; sinks) s.setScopeStack(ss); }

    void onPushScope()  { foreach (s; sinks) s.onPushScope(); }
    void onPopScope()   { foreach (s; sinks) s.onPopScope(); }
    void onScopeEmpty() { foreach (s; sinks) s.onScopeEmpty(); }

public:
    void putValue(in Value v) { foreach (s; sinks) s.putValue(v); }
}

class EnableDataSink : DataSink
{
    DataSink sink;
    ValueSrc!bool enable;

    this(DataSink sink, ValueSrc!bool en=null)
    {
        this.sink = enforce(sink, "sink is null");
        enable = en.or(new class ValueSrc!bool
                        {
                            override bool get() const { return true; }
                        });
    }

override:
    void setScopeStack(const(ScopeStack) ss) { sink.setScopeStack(ss); }

    protected void onPushScope()  { if (enable.get()) sink.onPushScope(); }
    protected void onPopScope()   { if (enable.get()) sink.onPopScope(); }
    protected void onScopeEmpty() { if (enable.get()) sink.onScopeEmpty(); }

    void putValue(in Value v) { if (enable.get()) sink.putValue(v); }
}
