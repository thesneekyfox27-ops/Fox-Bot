-- Real ten-pin scoring (strike/spare bonuses, bonus balls in the last frame).
-- `rolls` = list of pins knocked per ball, `n` = frames in the game (10, or 5 for a quick game).
Scoring = {}

-- Where a player is in their game: which frame/ball is next, how many pins are
-- standing for it, whether the rack is fresh, or done = true when finished.
function Scoring.state(rolls, n)
    local i, frame = 1, 1
    while frame < n do
        local r1 = rolls[i]
        if r1 == nil then return { frame = frame, roll = 1, standing = 10, reset = true } end
        if r1 == 10 then
            i, frame = i + 1, frame + 1
        else
            if rolls[i + 1] == nil then return { frame = frame, roll = 2, standing = 10 - r1, reset = false } end
            i, frame = i + 2, frame + 1
        end
    end
    local a, b, c = rolls[i], rolls[i + 1], rolls[i + 2]
    if a == nil then return { frame = n, roll = 1, standing = 10, reset = true } end
    if b == nil then
        if a == 10 then return { frame = n, roll = 2, standing = 10, reset = true } end
        return { frame = n, roll = 2, standing = 10 - a, reset = false }
    end
    if (a == 10 or a + b == 10) and c == nil then
        if a == 10 and b ~= 10 then return { frame = n, roll = 3, standing = 10 - b, reset = false } end
        return { frame = n, roll = 3, standing = 10, reset = true }
    end
    return { frame = n, done = true }
end

local function mark(v) if v == 0 then return '-' end return tostring(v) end

-- Score sheet: frames[f] = { marks = {'X'} / {'7','/'} / ..., total = running total or nil }
function Scoring.card(rolls, n)
    local frames, total, i = {}, 0, 1
    for f = 1, n do
        local fr = { marks = {} }
        local r1, r2, r3 = rolls[i], rolls[i + 1], rolls[i + 2]
        if f < n then
            if r1 == nil then
                -- not bowled yet
            elseif r1 == 10 then
                fr.marks = { 'X' }
                if r2 ~= nil and r3 ~= nil then total = total + 10 + r2 + r3; fr.total = total end
                i = i + 1
            else
                fr.marks[1] = mark(r1)
                if r2 ~= nil then
                    if r1 + r2 == 10 then
                        fr.marks[2] = '/'
                        if r3 ~= nil then total = total + 10 + r3; fr.total = total end
                    else
                        fr.marks[2] = mark(r2)
                        total = total + r1 + r2; fr.total = total
                    end
                end
                i = i + 2
            end
        else
            local a, b, c = r1, r2, r3
            if a ~= nil then fr.marks[1] = (a == 10) and 'X' or mark(a) end
            if b ~= nil then
                if a == 10 then fr.marks[2] = (b == 10) and 'X' or mark(b)
                else fr.marks[2] = (a + b == 10) and '/' or mark(b) end
            end
            if c ~= nil then
                if a == 10 and b ~= 10 then fr.marks[3] = (b + c == 10) and '/' or mark(c)
                else fr.marks[3] = (c == 10) and 'X' or mark(c) end
            end
            local st = Scoring.state(rolls, n)
            if st.done then
                total = total + (a or 0) + (b or 0) + (c or 0)
                fr.total = total
            end
        end
        frames[f] = fr
    end
    -- frames after an unscored frame must not show a total yet
    local blocked = false
    for f = 1, n do
        if blocked then frames[f].total = nil end
        if not frames[f].total then blocked = true end
    end
    return frames, Scoring.total(rolls, n)
end

-- Total so far (counts every ball bowled, plus bonuses already known)
function Scoring.total(rolls, n)
    local total, i = 0, 1
    for f = 1, n do
        local r1, r2, r3 = rolls[i], rolls[i + 1], rolls[i + 2]
        if r1 == nil then break end
        if f == n then
            total = total + r1 + (r2 or 0) + (r3 or 0)
            break
        end
        if r1 == 10 then
            total = total + 10 + (r2 or 0) + (r3 or 0); i = i + 1
        elseif r2 ~= nil and r1 + r2 == 10 then
            total = total + 10 + (r3 or 0); i = i + 2
        else
            total = total + r1 + (r2 or 0); i = i + 2
        end
    end
    return total
end

-- What to call a ball, given the pins standing before it and pins it knocked
function Scoring.callout(standingBefore, knocked)
    if standingBefore == 10 and knocked == 10 then return 'STRIKE!' end
    if knocked == standingBefore and knocked > 0 then return 'SPARE!' end
    if knocked == 0 then return 'GUTTER' end
    return (knocked == 1) and '1 PIN' or (knocked .. ' PINS')
end

-- Highest score still possible (every remaining ball knocks down everything left)
function Scoring.maxPossible(rolls, n)
    local r = {}
    for i, v in ipairs(rolls) do r[i] = v end
    for _ = 1, 30 do
        local st = Scoring.state(r, n)
        if st.done then break end
        r[#r + 1] = st.standing
    end
    return Scoring.total(r, n)
end
