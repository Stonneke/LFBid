-- DKP data table
-- Add or update entries in this format:
-- LFTentDKP = {
--     ["Player 1"] = { t1 = 120, t2 = 5 },
--     ["Player 2"] = { t1 = 5, t2 = 0 },
-- }

LFTentDKPDefaults = {
    
}

if type(LFTentDKP) ~= "table" or next(LFTentDKP) == nil then
    LFTentDKP = LFTentDKPDefaults
end

