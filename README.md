# bon

bon is a **serialization library** for the [Beef programming language](https://github.com/beefytech/Beef) and is designed to easily serialize and deserialize beef data structures.

## About

TALK ABOUT Bon... and BonEnv / settings reflection based nature

bon is a reflection based serialization libary. Serializing and deserializing of a type is done in one call to ``Bon.Serialize`` or ``Bon.Deserialize``.

HOW IT LOOKS LIKE

```bf
let structure = new State() {
		currentMode = .Playing,
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

```
{
	currentMode = .Playing,
	partyName = "ChaosCrew",
	playerInfo = <3>[
		{
			level = 2,
			gold = 231
		},
		{
			dead = true,
			level = 1
		}
	]
}
```

Bon can (with the exception of pointers) serialize and deserialize all beef structures. Primitives, Arrays and strings work out of the box, custom types need to be setup for use with bon (like structs, classes, enums, eunm unions, (arrays & boxed types)). 

LINK TO SERIALIZING

basic usage
config
marking
for more examples -> tests.bf

## How do i..?

## Serialization

```cs
int i = 15;
Bon.Serialize(i, outStr); // will output: 15
```

## Deserialization

## Extension

## Integrated usage

## Documentation

lots of how do i points here