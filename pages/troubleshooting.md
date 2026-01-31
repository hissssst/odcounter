# Troubleshooting

## No persistent term stored with this key...

It looks like this

```
** (ArgumentError) errors were found at the given arguments:

  * 1st argument: no persistent term stored with this key

    :persistent_term.get({ODCounter, <name>})
```

And it means that you didn't call `ODCounter.init(<name>)`.
Refer to `ODCounter.init/2` for more information

## counters array size is larger than the amount of keys I have

`ODCounter` reserves some extra memory for keys which may appear in runtime.

But if your counters array is larger than the amount you have + runtime_size, you may need to
remove `_build/env/odcounter.tab` and recompile whole project and every dependency. Thats caused
by current limitation of Elixir compiler
