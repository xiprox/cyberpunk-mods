**F on a dialog choice during a quest ride also skips the ride**

NightCoop bacb705 (protocol 143), Cyberpunk 2.5 (exe 3.0.88.46235). 3 players, I'm a guest (not tried as host).

**What happens**
In Panam's car the dialog choices and the scene's "Skip Ride [F]" prompt are on screen together. F on a choice casts my vote, and the same press skips the ride: the vote and the cutscene skip are logged in the same millisecond, then the car is teleported ~850 m to the end of the ride. The log says the skip goes to the partners too.

**How often**
2 of 2 tries, both on "How much do you know about Rocky Ridge?": vote #63 at 21:22:22 and vote #76 at 21:31:10 (scene 0x14fa37456a18f706, node 1753).

**Expected**
F on a choice only votes. Skip Ride shouldn't fire from the same press.

**Possible cause (a guess from the log)**
The vote takes the press ("our press") and the choice is applied ~370 ms later by a replayed press ("press replayed through the interaction manager"), so the real F press isn't used up by the choice and reaches the ride's skip, also on F.

**Log** (whole lines from nightcoop.log attached)
```
[21:31:10.995] [info ] dialog vote #76: we vote for option 4 'How much do you know about Rocky Ridge?' (item 0x302) (our press)
[21:31:10.995] [info ] scene skip: we skip the cutscene of scene 0x14fa37456a18f706 (node 1753: the player's "cancel") — the partners skip it at that node too: at once, or when theirs comes in this run of the scene (skip_cut_by_run)
[21:31:12.961] [warn ] vehicles: net id 0x0003dfac: our own quest car 0x897f60 was moved 853 m by our own game (a scene or quest teleport) ...
```

Also running: a small CET mod of mine that listens for ChoiceApply/Choice1 (RegisterInputListener, consumes nothing) and does nothing in a vehicle.
