module symmetry.imap.set;

///
struct Set(T) {
    bool[T] values_;
    alias values_ this;

    bool has(T value) {
        return (value in values_) !is null;
    }

    T[] values() const {
        import std.algorithm : filter, map;
        import std.array : array;
        import std.conv : to;
        return values_.keys.filter!(c => values_[c])
               .array;
    }

    string toString() const {
        import std.format : format;
        import std.algorithm : map, sort;
        import std.array : array;
        import std.string : join;
        import std.conv : to;
        return format!"[%s]"(values.map!(value => value.to!string).array.sort.array.join(","));
    }
}

///
Set!T add(T)(Set!T set, T value) {
    import std.algorithm : each;
    Set!T ret;
    set.values_.byKeyValue.each!(entry => ret[entry.key] = entry.value);
    ret.values_[value] = true;
    return ret;
}

///
Set!T remove(T)(Set!T set, T value) {
    import std.algorithm : each;
    Set!T ret;
    set.values_.byKeyValue.each!(entry => ret[entry.key] = entry.value);
    ret.remove(value);
    return ret;
}

