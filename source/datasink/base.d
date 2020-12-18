module datasink.base;

import std : Rebindable, enforce;

package import datasink.value;
package import datasink.typedesc;
package import datasink.util;

alias Scope = TypeDsc;
alias ScopeStack = Stack!Scope;

interface FieldSink
{
    void putIdent(string id);
    void putValue(in Value v);
}

interface DataSink : FieldSink
{
    void setScopeStack(const(ScopeStack));

    protected void onPushScope();
    protected void onPopScope();
}

final class NullDataSink : DataSink
{
override:
    void setScopeStack(const(ScopeStack)) { }
    protected void onPushScope() { }
    protected void onPopScope() { }
    void putIdent(string id) { }
    void putValue(in Value v) { }
}

abstract class BaseDataSink : DataSink
{
protected:
    Rebindable!(const(ScopeStack)) scopeStack;
    void onSetScopeStack() { } // reset state

public:

override:
    void setScopeStack(const(ScopeStack) ss)
    {
        scopeStack = enforce(ss, "scope stack is null");
        onSetScopeStack();
    }

abstract:
    protected void onPushScope();
    protected void onPopScope();
    void putIdent(string id);
    void putValue(in Value v);
}

class ListDataSink : DataSink
{
protected:
    DataSink[] sinks;

public:
    this(DataSink[] list) { sinks = list; }

override:
    void setScopeStack(const(ScopeStack) ss)
    { foreach (s; sinks) s.setScopeStack(ss); }

    protected void onPushScope() { foreach (s; sinks) s.onPushScope(); }
    protected void onPopScope()  { foreach (s; sinks) s.onPopScope(); }

    void putIdent(string id)  { foreach (s; sinks) s.putIdent(id); }
    void putValue(in Value v) { foreach (s; sinks) s.putValue(v); }
}

class EnableDataSink : DataSink
{
    DataSink sink;
    ValueSrc!bool enable;

    this(DataSink sink, ValueSrc!bool en=null)
    {
        this.sink = enforce(sink, "sink is null");
        enable = en.or(new class ValueSrc!bool { override bool get() const { return true; } });
    }

override:
    void setScopeStack(const(ScopeStack) ss) { sink.setScopeStack(ss); }

    protected void onPushScope() { if (enable.get()) sink.onPushScope(); }
    protected void onPopScope()  { if (enable.get()) sink.onPopScope(); }

    void putIdent(string id)  { if (enable.get()) sink.putIdent(id); }
    void putValue(in Value v) { if (enable.get()) sink.putValue(v); }
}

interface RootDataSink : FieldSink
{
    void pushScope(Scope);
    void popScope();

    final auto scopeGuard(Scope s)
    {
        pushScope(s);
        return ScopeGuard(&popScope);
    }

    final void putData(V)(in V val)
    {
        import std : Unqual, isArray, isAssociativeArray, isSomeString, ElementType;
        alias T = Unqual!V;

        uint getEnumIndex(E)(E e) if (is(E == enum))
        {
            import std : EnumMembers;
            static foreach (i, v; EnumMembers!E) if (v == e) return i;
            assert (0, "bad enum value");
        }

        static if (is(T == enum) && !is(T == Bool))
        {
            auto _ = scopeGuard(makeTypeDsc!T);
            putValue(Value(getEnumIndex(val)));
        }
        else
        static if (isArray!T &&
                  !isSomeString!T &&
                  !is(Unqual!(ElementType!T) == void))
        {
            auto _ = scopeGuard(makeTypeDsc!T);
            foreach (v; val) putData(v);
        }
        else
        static if (is(T == bool))
        {
            putValue(Value(cast(Bool)val));
        }
        else
        static if (is(typeof(Value(val))))
        {
            putValue(Value(val));
        }
        else
        {
            auto _ = scopeGuard(makeTypeDsc!T);

            static if (isAssociativeArray!T)
            {
                foreach (k, v; val)
                {
                    putData(k);
                    putData(v);
                }
            }
            else static if (isTaggedVariant!T)
            {
                putData(val.kind);
                val.visit!(v => putData(v));
            }
            else static if (is(T == struct))
            {
                foreach (i, ref v; val.tupleof)
                {
                    enum name = __traits(identifier, val.tupleof[i]);
                    putIdent(name);
                    putData(v);
                }
            }
            else static assert(0, "unsupported type: " ~ T.stringof);
        }
    }
}

final class BaseRootDataSink : RootDataSink
{
protected:
    ScopeStack scopeStack;
    DataSink sink;

public:
    this(DataSink sink, ScopeStack ss=null)
    {
        scopeStack = ss.or(new BaseStack!Scope(64));
        this.sink = enforce(sink, "sink is null");
        this.sink.setScopeStack(scopeStack);
    }

    void setScopeStack(ScopeStack ss)
    {
        scopeStack = enforce(ss, "scope stack is null");
        sink.setScopeStack(scopeStack);
    }

    void setSink(DataSink sink)
    {
        this.sink = enforce(sink, "sink is null");
        this.sink.setScopeStack(scopeStack);
    }

override:
    void pushScope(Scope s)
    {
        scopeStack.push(s);
        sink.onPushScope();
    }

    void popScope()
    {
        sink.onPopScope();
        scopeStack.pop();
    }

    void putIdent(string id) { sink.putIdent(id); }
    void putValue(in Value v) { sink.putValue(v); }
}

version (unittest)
{
    class TestScopeStack : BaseStack!Scope
    {
        alias T = Scope;
        T[] history;
        void drop() { history.length = 0; }

        override void push(T v)
        {
            super.push(v);
            history ~= v;
        }
    }

    class TestDataSink : BaseDataSink
    {
        string[] ids;
        Value[] vals;

        void drop()
        {
            ids.length = 0;
            vals.length = 0;
        }

    override:
        protected void onPushScope() { }
        protected void onPopScope() { }
        void putIdent(string id) { ids ~= id; }
        void putValue(in Value v) { vals ~= v; }
    }

    enum NumEnum { one = 1, two = 2 }

    enum StrEnum { one = "ONE", two = "TWO" }

    struct SimpleStruct
    {
        int field1;
        string field2;
    }

    struct NumEnumArrayStruct { NumEnum[] foos; }
    struct StrEnumArrayStruct { StrEnum[] fs; }
}

unittest
{
    auto ds = new TestDataSink;
    auto tss = new TestScopeStack;
    auto brds = new BaseRootDataSink(ds, tss);

    void drop()
    {
        ds.drop();
        assert (tss.empty, "not empty test stack on block end");
        tss.drop();
    }

    auto dropGuard()
    {
        assert (tss.empty, "not empty test stack on block start");
        return ScopeGuard(&drop);
    }

    {
        auto _ = dropGuard();
        brds.putData(10);
        assert (tss.history.length == 0);
        assert (ds.ids.length == 0);
        assert (ds.vals.length == 1);
        assert (ds.vals[0] != Value(cast(byte)10));
        assert (ds.vals[0] != Value(cast(ubyte)10));
        assert (ds.vals[0] != Value(cast(short)10));
        assert (ds.vals[0] != Value(cast(ushort)10));
        assert (ds.vals[0] == Value(10));
        assert (ds.vals[0] != Value(10U));
        assert (ds.vals[0] != Value(10L));
        assert (ds.vals[0] != Value(10UL));
        assert (ds.vals[0] != Value(10.0f));
        assert (ds.vals[0] != Value(10.0));
    }

    {
        auto _ = dropGuard();
        brds.putData(cast(ubyte)10);
        assert (tss.history.length == 0);
        assert (ds.ids.length == 0);
        assert (ds.vals.length == 1);
        assert (ds.vals[0] != Value(cast(byte)10));
        assert (ds.vals[0] == Value(cast(ubyte)10));
        assert (ds.vals[0] != Value(cast(short)10));
        assert (ds.vals[0] != Value(cast(ushort)10));
        assert (ds.vals[0] != Value(10));
        assert (ds.vals[0] != Value(10U));
        assert (ds.vals[0] != Value(10L));
        assert (ds.vals[0] != Value(10UL));
        assert (ds.vals[0] != Value(10.0f));
        assert (ds.vals[0] != Value(10.0));
    }

    {
        auto _ = dropGuard();
        brds.putData(10.0);
        assert (tss.history.length == 0);
        assert (ds.ids.length == 0);
        assert (ds.vals.length == 1);
        assert (ds.vals[0] != Value(cast(byte)10));
        assert (ds.vals[0] != Value(cast(ubyte)10));
        assert (ds.vals[0] != Value(cast(short)10));
        assert (ds.vals[0] != Value(cast(ushort)10));
        assert (ds.vals[0] != Value(10));
        assert (ds.vals[0] != Value(10U));
        assert (ds.vals[0] != Value(10L));
        assert (ds.vals[0] != Value(10UL));
        assert (ds.vals[0] != Value(10.0f));
        assert (ds.vals[0] == Value(10.0));
    }

    {
        auto _ = dropGuard();
        brds.putData("hello");
        assert (tss.history.length == 0);
        assert (ds.ids.length == 0);
        assert (ds.vals == [Value("hello")]);
    }

    {
        auto _ = dropGuard();
        void[] foo = [cast(ubyte)0xde, 0xad, 0xbe, 0xaf];
        brds.putData(foo);
        assert (tss.history.length == 0);
        assert (ds.ids.length == 0);
        assert (ds.vals.length == 1);
        assert (ds.vals[0].kind == Value.Kind.raw);
        assert (ds.vals[0].get!(const(void)[]) == foo);
    }

    {
        auto _ = dropGuard();
        auto foo = cast(Bool)true;
        brds.putData(foo);
        assert (tss.history.length == 0);
        assert (ds.ids.length == 0);
        assert (ds.vals.length == 1);
        assert (ds.vals[0].kind == Value.Kind.bit);
        assert (ds.vals[0].get!Bool == Bool.true_);
    }

    {
        auto _ = dropGuard();
        bool foo = true;
        brds.putData(foo);
        assert (tss.history.length == 0);
        assert (ds.ids.length == 0);
        assert (ds.vals.length == 1);
        assert (ds.vals[0].kind == Value.Kind.bit);
        assert (ds.vals[0].get!Bool == Bool.true_);
    }

    {
        auto _ = dropGuard();
        auto foo = SimpleStruct(12, "hello");
        brds.putData(foo);
        assert (tss.history.length == 1);
        assert (tss.history[0].kind == TypeDsc.Kind.object);
        assert (ds.ids == ["field1", "field2"]);
        assert (ds.vals.length == 2);
        assert (ds.vals[0].kind == Value.Kind.i32);
        assert (ds.vals[0].get!int == 12);
        assert (ds.vals[1].kind == Value.Kind.str);
        assert (ds.vals[1].get!string == "hello");
    }

    {
        auto _ = dropGuard();
        brds.putData(NumEnum.one);
        assert (tss.history.length == 1);
        assert (tss.history[0].kind == TypeDsc.Kind.enumEl);
        assert (ds.ids.length == 0);
        assert (ds.vals.length == 1);
        assert (ds.vals[0].kind == Value.Kind.u32);
        assert (ds.vals[0].get!uint == 0); // index of 'one'
    }

    {
        auto _ = dropGuard();
        const foo = NumEnumArrayStruct([NumEnum.one, NumEnum.two]);
        brds.putData(foo);
        size_t p;
        assert (tss.history[p++].kind == TypeDsc.Kind.object);
            assert (tss.history[p++].kind == TypeDsc.Kind.dArray);
                assert (tss.history[p++].kind == TypeDsc.Kind.enumEl); // one
                assert (tss.history[p++].kind == TypeDsc.Kind.enumEl); // two
        assert (tss.history.length == p);
        assert (ds.ids == ["foos"]);
        assert (ds.vals.length == 2);
        assert (ds.vals[0].kind == Value.Kind.u32);
        assert (ds.vals[0].get!uint == 0); // index of 'one'
        assert (ds.vals[1].kind == Value.Kind.u32);
        assert (ds.vals[1].get!uint == 1); // index of 'two'
    }

    {
        auto _ = dropGuard();
        StrEnumArrayStruct[2] foo = [
            StrEnumArrayStruct([StrEnum.one, StrEnum.one, StrEnum.two]),
            StrEnumArrayStruct([])
        ];
        brds.putData(foo);
        size_t p;
        assert (tss.history[p++].kind == TypeDsc.Kind.sArray);
            assert (tss.history[p++].kind == TypeDsc.Kind.object);
                assert (tss.history[p++].kind == TypeDsc.Kind.dArray);
                    assert (tss.history[p++].kind == TypeDsc.Kind.enumEl);
                    assert (tss.history[p++].kind == TypeDsc.Kind.enumEl);
                    assert (tss.history[p++].kind == TypeDsc.Kind.enumEl);
            assert (tss.history[p++].kind == TypeDsc.Kind.object);
                assert (tss.history[p++].kind == TypeDsc.Kind.dArray);
        assert (tss.history.length == p);
        assert (ds.ids == ["fs", "fs"]);
        assert (ds.vals.length == 3);
        assert (ds.vals[0].kind == Value.Kind.u32);
        assert (ds.vals[0].get!uint == 0);
        assert (ds.vals[1].get!uint == 0);
        assert (ds.vals[2].get!uint == 1);
    }

    assert (tss.empty);
}
