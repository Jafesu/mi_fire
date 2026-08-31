--- Pump behaviour that is not published fire service figures.
---
--- The hydraulics in `shared/hydraulics.lua` are real and are not tuning values. What is here
--- is the handful of numbers that describe how the *controls* behave, which no manual states
--- because they are properties of a particular pump rather than of water.

MIFirePump = {}

--- What a pump in gear makes at idle, before anyone touches the throttle.
---
--- Not zero. A pump in gear is already turning, which is why a line charges and reads
--- something before the operator has done anything -- and why forgetting the throttle gives a
--- soft line rather than a dead one.
MIFirePump.idlePsi = 40.0

--- How much one press of the throttle moves it, as a fraction of its travel.
MIFirePump.throttleStep = 0.05

--- Refresh rate of the panel while someone is looking at it, in ms.
---
--- The plan's figure. A live panel is twenty-odd animated gauges and pushing state at frame
--- rate from Lua is the obvious way to make a pump panel cost more than the fire does.
MIFirePump.panelRefreshMs = 100
