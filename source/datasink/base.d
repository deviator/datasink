module datasink.base;

package import std : Rebindable, enforce;
package import datasink.value;
package import datasink.typedesc;
package import datasink.util;

struct AAKey { }
struct AAValue { }
struct ArrayLength { }

alias Ident = TaggedVariant!(
    ["none",     "name",  "index", "aaKey", "aaValue", "length"],
    typeof(null), string,  ulong,   AAKey,   AAValue,  ArrayLength
);

const AAKeyIdent = Ident(AAKey.init);
const AAValueIdent = Ident(AAValue.init);
const ArrayLengthIdent = Ident(ArrayLength.init);

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
    void putValue(in Value v);
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
    void putValue(in Value v) { sink.putValue(v); }
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
    abstract void putValue(in Value v);
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
    abstract void putValue(in Value v);

    auto scopeGuard(Scope s)
    {
        pushScope(s);
        return ScopeGuard(&popScope);
    }

    final void putData(V)(in V val, Ident id=Ident(null))
    {
        import std : Unqual, isArray, isDynamicArray,
                     isAssociativeArray, isSomeString,
                     ElementType;
        alias T = Unqual!V;

        uint getEnumIndex(E)(E e) if (is(E == enum))
        {
            import std : EnumMembers;
            static foreach (i, v; EnumMembers!E) if (v == e) return i;
            assert (0, "bad enum value");
        }

        // see tmpIdent description
        if (id.isNull && !tmpIdent.isNull)
        {
            id = tmpIdent.get();
            tmpIdent.nullify();
        }

        static immutable tdsc = makeTypeDsc!T;
        auto _ = scopeGuard(Scope(tdsc, id));

        static if (is(T == enum) && !is(T == Bool))
        {
            putValue(Value(getEnumIndex(val)));
        }
        else
        static if (isArray!T &&
                  !isSomeString!T &&
                  !is(Unqual!(ElementType!T) == void))
        {
            static if (isDynamicArray!T)
                putData(cast(ulong)val.length, ArrayLengthIdent);
            foreach (i, v; val) putData(v, Ident(i));
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
            putData(cast(ulong)val.length, ArrayLengthIdent);
            foreach (k, v; val)
            {
                putData(k, AAKeyIdent);
                putData(v, AAValueIdent);
            }
        }
        else
        static if (isTaggedVariant!T)
        {
            putData(val.kind);
            const kindIndex = getEnumIndex(val.kind);
            val.visit!(v => putData(v, Ident(kindIndex)));
        }
        else
        static if (is(T == Tuple!X, X...))
        {
            foreach (i, ref v; val.tupleof)
                putData(v, Ident(i));
        }
        else
        static if (is(T == struct))
        {
            foreach (i, ref v; val.tupleof)
            {
                enum name = __traits(identifier, val.tupleof[i]);
                putData(v, Ident(name));
            }
        }
        else static assert(0, "unsupported type: " ~ T.stringof);
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
        Value[] vals;
        void drop() { vals.length = 0; }
    override:
        protected void onPushScope() { }
        protected void onPopScope() { }
        protected void onScopeEmpty() { }
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
        assert (ds.vals[0].kind == Value.Kind.u32);
        assert (ds.vals[0].get!uint == 0); // index of 'one'
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
                assert (tss.history[p].id == ArrayLengthIdent);
                p++;
                assert (tss.history[p].dsc.kind == TypeDsc.Kind.enumEl);
                assert (tss.history[p].id == Ident(0));
                p++;
                assert (tss.history[p].dsc.kind == TypeDsc.Kind.enumEl);
                assert (tss.history[p].id == Ident(1));
                p++;
        assert (tss.history.length == p);
        assert (ds.vals.length == 3);

        assert (ds.vals == [Value(2UL), Value(0U), Value(1U)]); // index of 'one' and 'two'
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
                    assert (tss.history[p].id == ArrayLengthIdent);
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
                    assert (tss.history[p].id == ArrayLengthIdent);
                    p++;
        assert (tss.history.length == p);
        assert (ds.vals == [Value(3UL), Value(0U), Value(0U), Value(1U), Value(0UL)]);
    }

    assert (tss.empty);
}
