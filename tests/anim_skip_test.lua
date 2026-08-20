-- Standalone unit test for Anim Skip and Audio Overlap prevention
-- Run with: luajit tests/anim_skip_test.lua

local function assertEq(actual, expected, desc)
  if actual ~= expected then
    error(string.format("FAIL: %s (expected %s, got %s)", desc, tostring(expected), tostring(actual)), 2)
  end
  print(string.format("PASS: %s", desc))
end

print("=== Testing Anim Skip & Audio Overlap Logic ===")

-- 1. Active sound tracking and force stopping
do
  local activeSounds = {}
  local function setActiveSound(src)
    if not src then return end
    activeSounds[src] = true
  end
  local function stopActiveSound()
    for src in pairs(activeSounds) do
      pcall(function()
        if src.stop then src:stop() end
      end)
    end
    activeSounds = {}
  end

  local s1_stopped = false
  local s2_stopped = false
  local s1 = { stop = function() s1_stopped = true end }
  local s2 = { stop = function() s2_stopped = true end }

  setActiveSound(s1)
  setActiveSound(s2)
  assertEq(s1_stopped, false, "sound 1 not stopped initially")
  assertEq(s2_stopped, false, "sound 2 not stopped initially")

  stopActiveSound()
  assertEq(s1_stopped, true, "stopActiveSound stops sound 1")
  assertEq(s2_stopped, true, "stopActiveSound stops sound 2")
  assertEq(next(activeSounds), nil, "activeSounds table is empty after stopActiveSound")
end

-- 2. Audio Overlap Prevention simulation
do
  local activeSounds = {}
  local function setActiveSound(src)
    if not src then return end
    activeSounds[src] = true
  end
  local function stopActiveSound()
    for src in pairs(activeSounds) do
      pcall(function()
        if src.stop then src:stop() end
      end)
    end
    activeSounds = {}
  end

  local function playSound(name, animSkipEnabled)
    if animSkipEnabled then
      stopActiveSound()
    end
    local stopped = false
    local src = {
      name = name,
      stop = function() stopped = true end,
      isStopped = function() return stopped end,
    }
    if animSkipEnabled then
      setActiveSound(src)
    end
    return src
  end

  -- With Anim Skip ON: Sound 1 force-stopped before Sound 2 plays
  local cry = playSound("Cry_Pikachu", true)
  assertEq(cry.isStopped(), false, "Cry started playing")
  
  local levelUp = playSound("Level_Up", true)
  assertEq(cry.isStopped(), true, "Cry force-stopped when Level_Up starts")
  assertEq(levelUp.isStopped(), false, "Level_Up started playing")

  local moveSound = playSound("Thunderbolt", true)
  assertEq(levelUp.isStopped(), true, "Level_Up force-stopped when move sound starts")
  assertEq(moveSound.isStopped(), false, "Move sound started playing")

  -- With Anim Skip OFF: Sound 1 is not stopped when Sound 2 plays
  local cry2 = playSound("Cry_Charmander", false)
  local moveSound2 = playSound("Ember", false)
  assertEq(cry2.isStopped(), false, "Anim Skip OFF: Cry 2 not stopped by Ember")
  assertEq(moveSound2.isStopped(), false, "Anim Skip OFF: Ember playing")
end

-- 3. Battle Animation skipping with A button
do
  local function skipAnimOrAudio(battle, stopActiveSoundFn)
    if not battle then return false end
    local input = battle.game and battle.game.input
    if not input or not input:wasPressed("a") then return false end

    local skipped = false

    if battle.animPlaying then
      if stopActiveSoundFn then stopActiveSoundFn() end
      if battle.waitingSound then
        pcall(function() if battle.waitingSound.stop then battle.waitingSound:stop() end end)
        battle.waitingSound = nil
      end
      if battle.animPlayer then
        if type(battle.animPlayer.finish) == "function" then
          pcall(battle.animPlayer.finish, battle.animPlayer)
        elseif type(battle.animPlayer.stop) == "function" then
          pcall(battle.animPlayer.stop, battle.animPlayer)
        end
      end
      battle.animPlaying = false
      if battle.pendingHit then
        if type(battle.applyHitFx) == "function" then
          battle:applyHitFx(battle.pendingHit)
        end
        battle.pendingHit = nil
      end
      if type(battle.resetPicFx) == "function" then
        battle:resetPicFx()
      end
      battle.waitFrames = 0
      if battle.fx then
        battle.fx.shake = nil
        battle.fx.flash = nil
      end
      battle.current = nil
      skipped = true
    end

    if battle.anim then
      if stopActiveSoundFn then stopActiveSoundFn() end
      battle.anim = nil
      if type(battle.advanceQueue) == "function" then
        battle:advanceQueue()
      end
      skipped = true
    end

    if battle.waitingSound then
      pcall(function() if battle.waitingSound.stop then battle.waitingSound:stop() end end)
      battle.waitingSound = nil
      if stopActiveSoundFn then stopActiveSoundFn() end
      battle.waitFrames = 0
      skipped = true
    end

    if battle.phase == "messages" then
      if battle.shown and battle.codes and #battle.shown > 0 then
        local cur = battle.shown[#battle.shown]
        if cur and #cur < #battle.codes then
          while #cur < #battle.codes do
            cur[#cur + 1] = battle.codes[#cur + 1]
            battle.charIndex = (battle.charIndex or 0) + 1
          end
          battle.charTimer = 0
          skipped = true
        end
      end

      if (battle.msgPreWait or 0) > 0 then
        battle.msgPreWait = 0
        skipped = true
      end
      if (battle.msgPromptWait or 0) > 0 then
        battle.msgPromptWait = 0
        skipped = true
      end

      if battle.msgPrompt then
        battle.msgPrompt = nil
        battle.current = nil
        if battle.waitingSound then
          pcall(function() if battle.waitingSound.stop then battle.waitingSound:stop() end end)
          battle.waitingSound = nil
        end
        if stopActiveSoundFn then stopActiveSoundFn() end
        skipped = true
      end

      if battle.msgWaiting then
        battle.msgWaiting = nil
        if type(battle.beginMsgLine) == "function" then
          battle:beginMsgLine()
        end
        battle.waitFrames = 0
        skipped = true
      end

      if battle.current and battle.current.auto then
        battle.msgAutoWait = 0
        battle.msgHold = true
        battle.current = nil
        skipped = true
      end
    end

    return skipped
  end

  -- Test Gen 1 Move Animation Skip
  local hitApplied = false
  local animFinished = false
  local picReset = false
  local soundStopped = false
  local battleG1 = {
    game = { input = { wasPressed = function(_, k) return k == "a" end } },
    animPlaying = true,
    animPlayer = { finish = function() animFinished = true end },
    pendingHit = { dmg = 25 },
    applyHitFx = function(_, hit) hitApplied = (hit.dmg == 25) end,
    resetPicFx = function() picReset = true end,
    waitFrames = 30,
    fx = { shake = 24, flash = 16 },
  }

  local res = skipAnimOrAudio(battleG1, function() soundStopped = true end)
  assertEq(res, true, "Gen 1 animation skip returned true")
  assertEq(battleG1.animPlaying, false, "animPlaying is false")
  assertEq(animFinished, true, "animPlayer finished")
  assertEq(hitApplied, true, "hit FX applied")
  assertEq(battleG1.pendingHit, nil, "pendingHit cleared")
  assertEq(picReset, true, "pic FX reset")
  assertEq(battleG1.waitFrames, 0, "waitFrames zeroed")
  assertEq(battleG1.fx.shake, nil, "screen shake cleared")
  assertEq(battleG1.fx.flash, nil, "screen flash cleared")
  assertEq(soundStopped, true, "active move sound stopped")

  -- Test Gen 2 Move Animation Skip
  local advanced = false
  local battleG2 = {
    game = { input = { wasPressed = function(_, k) return k == "a" end } },
    anim = { step = function() return true end },
    advanceQueue = function() advanced = true end,
  }
  res = skipAnimOrAudio(battleG2)
  assertEq(res, true, "Gen 2 animation skip returned true")
  assertEq(battleG2.anim, nil, "anim cleared")
  assertEq(advanced, true, "advanceQueue called")

  -- Test Pokemon Cry Skip
  local cryStopped = false
  local battleCry = {
    game = { input = { wasPressed = function(_, k) return k == "a" end } },
    waitingSound = { stop = function() cryStopped = true end },
    waitFrames = 45,
  }
  res = skipAnimOrAudio(battleCry)
  assertEq(res, true, "Cry skip returned true")
  assertEq(cryStopped, true, "Cry source stopped")
  assertEq(battleCry.waitingSound, nil, "waitingSound cleared")
  assertEq(battleCry.waitFrames, 0, "waitFrames zeroed")

  -- Test Level Up Jingle & Text Skip
  local jingleStopped = false
  local battleLevelUp = {
    game = { input = { wasPressed = function(_, k) return k == "a" end } },
    phase = "messages",
    codes = { 0x50, 0x69, 0x64, 0x67, 0x65, 0x79 },
    shown = { { 0x50, 0x69 } },
    charIndex = 2,
    charTimer = 3,
    msgPrompt = true,
    msgPromptWait = 3,
    waitingSound = { stop = function() jingleStopped = true end },
  }
  res = skipAnimOrAudio(battleLevelUp)
  assertEq(res, true, "Level Up skip returned true")
  assertEq(#battleLevelUp.shown[1], 6, "Text filled completely")
  assertEq(battleLevelUp.charTimer, 0, "charTimer reset")
  assertEq(battleLevelUp.msgPromptWait, 0, "msgPromptWait cleared")
  assertEq(battleLevelUp.msgPrompt, nil, "msgPrompt dismissed")
  assertEq(jingleStopped, true, "Level Up jingle force-stopped")
  assertEq(battleLevelUp.waitingSound, nil, "waitingSound cleared")

  -- Test No A Press -> No Skip
  local battleIdle = {
    game = { input = { wasPressed = function(_, k) return false end } },
    animPlaying = true,
  }
  res = skipAnimOrAudio(battleIdle)
  assertEq(res, false, "No A-press returned false")
  assertEq(battleIdle.animPlaying, true, "animPlaying remained true")
end

-- 4. Overworld item get fanfare & textbox skip with A button
do
  local function skipTextBox(box, stopActiveSoundFn)
    if not box then return false end
    local input = box.game and box.game.input
    if not input or not (input:wasPressed("a") or input:wasPressed("b")) then return false end

    local skipped = false

    if box.preSound or box.preSrc then
      if stopActiveSoundFn then stopActiveSoundFn() end
      if box.preSrc then
        pcall(function() if box.preSrc.stop then box.preSrc:stop() end end)
        box.preSrc = nil
      end
      box.preSound = nil
      skipped = true
    end

    if box.auto then
      if stopActiveSoundFn then stopActiveSoundFn() end
      if box.autoSrc then
        pcall(function() if box.autoSrc.stop then box.autoSrc:stop() end end)
        box.autoSrc = nil
      end
      box.auto = nil
      if box.done then
        if box.game and box.game.stack and type(box.game.stack.pop) == "function" then
          box.game.stack:pop()
        end
        if box.onDone then box.onDone() end
        return true
      end
      skipped = true
    end

    if (box.holdFrames or 0) > 0 then
      box.holdFrames = 0
      skipped = true
    end
    if (box.preWait or 0) > 0 then
      box.preWait = 0
      skipped = true
    end

    return skipped
  end

  -- Test "Red got Oak's Parcel!" item get fanfare skip
  local itemSoundStopped = false
  local popped = false
  local onDoneCalled = false

  local itemBox = {
    game = {
      input = { wasPressed = function(_, k) return k == "a" end },
      stack = { pop = function() popped = true end },
    },
    done = true,
    auto = {
      sound = function() return { stop = function() itemSoundStopped = true end } end,
      wait = true,
    },
    autoSrc = { stop = function() itemSoundStopped = true end },
    onDone = function() onDoneCalled = true end,
  }

  local skipped = skipTextBox(itemBox, function() itemSoundStopped = true end)
  assertEq(skipped, true, "skipTextBox skipped item fanfare")
  assertEq(itemSoundStopped, true, "Item fanfare sound stopped")
  assertEq(itemBox.auto, nil, "box.auto cleared")
  assertEq(popped, true, "TextBox popped from game stack")
  assertEq(onDoneCalled, true, "onDone callback invoked to continue script")

  -- Test pre-sound skip (e.g. Cinnabar quiz sound)
  local preStopped = false
  local quizBox = {
    game = { input = { wasPressed = function(_, k) return k == "a" end } },
    preSrc = { stop = function() preStopped = true end },
    preSound = function() end,
  }
  skipped = skipTextBox(quizBox)
  assertEq(skipped, true, "preSound skipped")
  assertEq(preStopped, true, "preSound source stopped")
  assertEq(quizBox.preSrc, nil, "preSrc cleared")
  assertEq(quizBox.preSound, nil, "preSound cleared")

  -- Test No A/B press -> does not skip
  local idleBox = {
    game = { input = { wasPressed = function() return false end } },
    auto = { wait = true },
    done = true,
  }
  skipped = skipTextBox(idleBox)
  assertEq(skipped, false, "No A-press returned false for TextBox")
  assertEq(idleBox.auto ~= nil, true, "auto kept when no button pressed")
end

print("=== All Anim Skip & Audio Overlap tests passed successfully! ===")
