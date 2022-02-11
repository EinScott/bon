# bon

bon is a **serialization library** for the [Beef programming language](https://github.com/beefytech/Beef) and is designed to easily serialize and deserialize beef data structures.

## Basics

bon is a reflection based serialization libary. (De-) Serialization of a value is done in one call to ``Bon.Serialize`` or ``Bon.Deserialize``.
Any value (though pointer support is limited) can be passed into these calls to produce a valid result (or, in the case of Deserialization, a precise error).

Primitives and strings (as well as [some common corlib types](#included-serialize-handlers), such as ``List<T>``) are supported by default. To support other custom types, reflection data for them simply needs to be included in the build.

For example, assuming that all types used below use the build settings or the ``[BonTarget]`` Attribute to include reflection data for them, this structure results in the following serialized bon output.

```bf
let structure = new State() {
		currentMode = .Battle(5),
		playerInfo = new List<PlayerInfo>() {
			.() {
				gold = 231,
				level = 2,
				dead = false
			},
			.() {
				gold = 0,
				level = 1,
				dead = true
			},
			default
		},
		partyName = new String("ChaosCrew")
	};

gBonEnv.serializeFlags |= .Verbose; // Output is formatted for editing & readability
let serialized = Bon.Serialize(structure, .. scope String());
```

Content of ``serialized``:
```
{
	partyName = "ChaosCrew",
	currentMode = .Battle{
		stage = 5
	},
	playerInfo = <3>[
		{
			level = 2,
			gold = 231
		},
		{
			level = 1
			dead = true,
		}
	]
}
```

As you can see, the output omits default values but without loosing information in the process. This, among other behaviours, is configurable just like we added the ``.Verbose`` flag above to receive a formatted and more extensive output. Bon's [configuration](#bonenvironment) is contained in a ``BonEnvironment`` object, that is passed into every call. By default, the global environment ``gBonEnv`` is used.

For an extensive overview of bon's capabilites, see [Documentation](#documentation) and [Tests](https://github.com/EinScott/bon/blob/main/Tests/src/Test.bf).

## How do i..?

## Serialization

```cs
int i = 15;
Bon.Serialize(i, outStr); // outStr: "15"
```

## Deserialization

## Documentation

TODO

### Syntax

every token meaning
file structure

### Type setup

what attributes do
the attributes BonTarget and BonPolyRegister don't need to be used
BonTarget -> just does reflection force for you, can also be done in build settings
polymorphism handling
BonPolyRegister -> types can also be registered into BonEnv manually by calling RegisterPolyType!(type)
how to force reflection data in the IDE...

### BonEnvironment

Newly created environments are independent from it, but start out with a copy of its state.

flags & handlers, how to reset default config

### Extension

basically some pointers on writing handlers
..?

### Included serialize handlers

### Integrated usage
