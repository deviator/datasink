module datasink.base;

package import std : Rebindable, enforce;
package import datasink.value;
package import datasink.typedesc;
package import datasink.util;

struct AAKey { }
struct AAValue { }

alias Ident = TaggedVariant!(
    ["none",     "name",  "index", "aaKey", "aaValue"],
    typeof(null), string,  ulong,   AAKey,   AAValue
);

const AAKeyIdent = Ident(AAKey.init);
const AAValueIdent = Ident(AAValue.init);

struct Scope
{
    TypeDsc dsc;
    Ident id;
}

alias ScopeStack = Stack!Scope;

interface DataSink
{
protected:
    void setScopeStack(const(ScopeStack));
    void onPushScope();
    void onPopScope();
    void onScopeEmpty();

public:
    /// put dynamic and associative arrays length before values
    void putLength(ulong ln);
    void putValue(in Value v);
    void putEnum(in EnumDsc dsc, ulong i);
}

version (unittest)
class PublicDataSink
{
    DataSink sink;
    this(DataSink s) { sink = enforce(s, "null sink"); }
    void setScopeStack(const(ScopeStack) ss) { sink.setScopeStack(ss); }
    void onPushScope() { sink.onPushScope(); }
    void onPopScope() { sink.onPopScope(); }
    void onScopeEmpty() { sink.onScopeEmpty(); }

    void putLength(ulong l) { sink.putLength(l); }
    void putValue(in Value v) { sink.putValue(v); }
    void putEnum(in EnumDsc dsc, ulong i) { sink.putEnum(dsc, i); }
}

abstract class BaseDataSink : DataSink
{
protected:
    Rebindable!(const(ScopeStack)) scopeStack;
    void onSetScopeStack() { } // reset state

    override void setScopeStack(const(ScopeStack) ss)
    {
        scopeStack = enforce(ss, "scope stack is null");
        onSetScopeStack();
    }

    abstract
    {
        void onPushScope();
        void onPopScope();
        void onScopeEmpty();
    }

public:
    abstract void putLength(ulong l);
    abstract void putValue(in Value v);
    abstract void putEnum(in EnumDsc dsc, ulong i);
}


abstract class RootDataSink
{
    /++ tmpIdent need if next put data type are not known,
        for example in case when RootDataSink passed to function that
        generate data, but embracing data are started output
    +/
    protected Nullable!Ident tmpIdent;
    final void setTmpIdent(Ident id) { tmpIdent = id; }

    abstract void pushScope(Scope);
    abstract void popScope();

    abstract void putLength(ulong l);
    abstract void putValue(in Value v);
    abstract void putEnum(in EnumDsc dsc, ulong i);

    auto scopeGuard(Scope s)
    {
        pushScope(s);
        return ScopeGuard(&popScope);
    }

    final void putData(V)(in V value, Ident ident=Ident(null))
    {
        import std : Unqual, isArray, isDynamicArray,
                     isAssociativeArray, isSomeString,
                     ElementType;

        uint getEnumIndex(E)(E e) if (is(E == enum))
        {
            import std : EnumMembers;
            static foreach (i, v; EnumMembers!E) if (v == e) return i;
            assert (0, "bad enum value");
        }

        void impl(W)(in W val, Ident id)
        {
            alias T = Unqual!W;

            // see tmpIdent description
            if (id.isNull && !tmpIdent.isNull)
            {
                id = tmpIdent.get();
                tmpIdent.nullify();
            }

            static immutable tdsc = makeTypeDsc!T;
            pushScope(Scope(tdsc, id));
            scope (exit) popScope();

            static if (is(T == enum) && !is(T == Bool))
            {
                putEnum(tdsc.get!EnumDsc, getEnumIndex(val));
            }
            else
            static if (isArray!T &&
                    !isSomeString!T &&
                    !is(Unqual!(ElementType!T) == void))
            {
                static if (isDynamicArray!T) putLength(val.length);
                foreach (i, v; val) impl(v, Ident(i));
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
            static if (isAssociativeArray!T)
            {
                putLength(val.length);
                foreach (k, v; val)
                {
                    impl(k, AAKeyIdent);
                    impl(v, AAValueIdent);
                }
            }
            else
            static if (isTaggedVariant!T)
            {
                impl(val.kind);
                const kindIndex = getEnumIndex(val.kind);
                val.visit!(v => impl(v, Ident(kindIndex)));
            }
            else
            static if (is(T == Tuple!X, X...))
            {
                putLength(val.tupleof.length);
                foreach (i, ref v; val.tupleof)
                    impl(v, Ident(i));
            }
            else
            static if (is(T == struct))
            {
                putLength(val.tupleof.length);
                foreach (i, ref v; val.tupleof)
                {
                    enum name = __traits(identifier, val.tupleof[i]);
                    impl(v, Ident(name));
                }
            }
            else static assert(0, "unsupported type: " ~ T.stringof);
        }

        impl(value, ident);
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
        if (scopeStack.empty)
            sink.onScopeEmpty();
    }

    void putLength(ulong l) { sink.putLength(l); }
    void putValue(in Value v) { sink.putValue(v); }
    void putEnum(in EnumDsc dsc, ulong i) { sink.putEnum(dsc, i); }
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
        Value[] vals;
        void drop() { vals.length = 0; }
    override:
        protected void onPushScope() { }
        protected void onPopScope() { }
        protected void onScopeEmpty() { }
        void putLength(ulong l) { }
        void putValue(in Value v) { vals ~= v; }
        void putEnum(in EnumDsc dsc, ulong i)
        { vals ~= dsc.def[i].value; }
    }

    enum NumEnum { one = 11, two = 22 }

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
        assert (tss.history == [Scope(TypeDsc(Value.Kind.i32), Ident(null))]);
        assert (ds.vals == [Value(10)]);
        assert (ds.vals[0].kind == Value.Kind.i32);
    }

    {
        auto _ = dropGuard();
        brds.putData(cast(ubyte)10);
        assert (tss.history == [Scope(TypeDsc(Value.Kind.u8), Ident(null))]);
        assert (ds.vals == [Value(cast(ubyte)10)]);
        assert (ds.vals[0].kind == Value.Kind.u8);
    }

    {
        auto _ = dropGuard();
        brds.putData(10.0);
        assert (tss.history == [Scope(TypeDsc(Value.Kind.f64), Ident(null))]);
        assert (ds.vals == [Value(10.0)]);
        assert (ds.vals[0].kind == Value.Kind.f64);
    }

    {
        auto _ = dropGuard();
        brds.putData("hello");
        assert (tss.history == [Scope(TypeDsc(Value.Kind.str), Ident(null))]);
        assert (ds.vals == [Value("hello")]);
    }

    {
        auto _ = dropGuard();
        void[] foo = [cast(ubyte)0xde, 0xad, 0xbe, 0xaf];
        brds.putData(foo);
        assert (tss.history == [Scope(TypeDsc(Value.Kind.raw), Ident(null))]);
        assert (ds.vals == [Value(foo)]);
        assert (ds.vals[0].kind == Value.Kind.raw);
        assert (ds.vals[0].get!(const(void)[]) == foo);
    }

    {
        auto _ = dropGuard();
        auto foo = cast(Bool)true;
        brds.putData(foo);
        assert (tss.history == [Scope(TypeDsc(Value.Kind.bit), Ident(null))]);
        assert (ds.vals.length == 1);
        assert (ds.vals[0].kind == Value.Kind.bit);
        assert (ds.vals[0].get!Bool == Bool.true_);
    }

    {
        auto _ = dropGuard();
        bool foo = true;
        brds.putData(foo);
        assert (tss.history == [Scope(TypeDsc(Value.Kind.bit), Ident(null))]);
        assert (ds.vals.length == 1);
        assert (ds.vals[0].kind == Value.Kind.bit);
        assert (ds.vals[0].get!Bool == Bool.true_);
    }

    {
        auto _ = dropGuard();
        auto foo = SimpleStruct(12, "hello");
        brds.putData(foo);
        size_t p;

        assert (tss.history[p].dsc.kind == TypeDsc.Kind.object);
        assert (tss.history[p].id == Ident(null));
        p++;
        assert (tss.history[p].dsc == TypeDsc(Value.Kind.i32));
        assert (tss.history[p].id == Ident("field1"));
        p++;
        assert (tss.history[p].dsc == TypeDsc(Value.Kind.str));
        assert (tss.history[p].id == Ident("field2"));
        p++;
        assert (tss.history.length == p);

        assert (ds.vals.length == 2);
        assert (ds.vals[0].kind == Value.Kind.i32);
        assert (ds.vals[0].get!int == 12);
        assert (ds.vals[1] == Value("hello"));
    }

    {
        auto _ = dropGuard();
        brds.putData(NumEnum.one);
        assert (tss.history.length == 1);
        assert (tss.history[0].dsc.kind == TypeDsc.Kind.enumEl);
        assert (tss.history[0].dsc.get!EnumDsc.def.length == 2);
        assert (ds.vals.length == 1);
        assert (ds.vals[0] == Value(11));
    }

    {
        auto _ = dropGuard();
        const foo = NumEnumArrayStruct([NumEnum.one, NumEnum.two]);
        brds.putData(foo);
        size_t p;
        assert (tss.history[p].dsc.kind == TypeDsc.Kind.object);
        assert (tss.history[p].id == Ident(null));
            p++;
            assert (tss.history[p].dsc.kind == TypeDsc.Kind.dArray);
            assert (tss.history[p].id == Ident("foos"));
            p++;
                assert (tss.history[p].dsc.kind == TypeDsc.Kind.enumEl);
                assert (tss.history[p].id == Ident(0));
                p++;
                assert (tss.history[p].dsc.kind == TypeDsc.Kind.enumEl);
                assert (tss.history[p].id == Ident(1));
                p++;
        assert (tss.history.length == p);
        assert (ds.vals.length == 2);

        assert (ds.vals == [Value(11), Value(22)]);
    }

    {
        auto _ = dropGuard();
        StrEnumArrayStruct[2] foo = [
            StrEnumArrayStruct([StrEnum.one, StrEnum.one, StrEnum.two]),
            StrEnumArrayStruct([])
        ];
        brds.putData(foo);
        size_t p;
        assert (tss.history[p].dsc.kind == TypeDsc.Kind.sArray);
        assert (tss.history[p].id == Ident(null));
        p++;
            assert (tss.history[p].dsc.kind == TypeDsc.Kind.object);
            assert (tss.history[p].id == Ident(0));
            p++;
                assert (tss.history[p].dsc.kind == TypeDsc.Kind.dArray);
                assert (tss.history[p].id == Ident("fs"));
                p++;
                    assert (tss.history[p].dsc.kind == TypeDsc.Kind.enumEl);
                    assert (tss.history[p].id == Ident(0));
                    p++;
                    assert (tss.history[p].dsc.kind == TypeDsc.Kind.enumEl);
                    assert (tss.history[p].id == Ident(1));
                    p++;
                    assert (tss.history[p].dsc.kind == TypeDsc.Kind.enumEl);
                    assert (tss.history[p].id == Ident(2));
                    p++;
            assert (tss.history[p].dsc.kind == TypeDsc.Kind.object);
            assert (tss.history[p].id == Ident(1));
            p++;
                assert (tss.history[p].dsc.kind == TypeDsc.Kind.dArray);
                assert (tss.history[p].id == Ident("fs"));
                p++;
        assert (tss.history.length == p);
        assert (ds.vals == [Value("ONE"), Value("ONE"), Value("TWO")]);
    }

    assert (tss.empty);
}
