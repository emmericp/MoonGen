--[[
        luaunit.lua

Description: A unit testing framework
Homepage: https://github.com/bluebird75/luaunit
Development by Philippe Fremy <phil@freehackers.org>
Based on initial work of Ryu, Gwang (http://www.gpgstudy.com/gpgiki/LuaUnit)
License: BSD License, see LICENSE.txt
Version: 3.0
]]--

local M={}

-- private exported functions (for testing)
M.private = {}

M.VERSION='3.1'

--[[ Some people like assertEquals( actual, expected ) and some people prefer 
assertEquals( expected, actual ).
]]--
M.ORDER_ACTUAL_EXPECTED = true
M.PRINT_TABLE_REF_IN_ERROR_MSG = false
M.LINE_LENGTH=80

-- set this to false to debug luaunit
local STRIP_LUAUNIT_FROM_STACKTRACE=true

M.VERBOSITY_DEFAULT = 10
M.VERBOSITY_LOW     = 1
M.VERBOSITY_QUIET   = 0
M.VERBOSITY_VERBOSE = 20

-- set EXPORT_ASSERT_TO_GLOBALS to have all asserts visible as global values
-- EXPORT_ASSERT_TO_GLOBALS = true

-- we need to keep a copy of the script args before it is overriden
local cmdline_argv = rawget(_G, "arg")

M.USAGE=[[Usage: lua <your_test_suite.lua> [options] [testname1 [testname2] ... ]
Options:
  -h, --help:             Print this help
  --version:              Print version information
  -v, --verbose:          Increase verbosity
  -q, --quiet:            Set verbosity to minimum
  -o, --output OUTPUT:    Set output type to OUTPUT
                          Possible values: text, tap, junit, nil
  -n, --name NAME:        For junit only, mandatory name of xml file
  -p, --pattern PATTERN:  Execute all test names matching the lua PATTERN
                          May be repeated to include severals patterns
                          Make sure you esape magic chars like +? with %
  testname1, testname2, ... : tests to run in the form of testFunction,
                              TestClass or TestClass.testMethod
]]

----------------------------------------------------------------
--
--                 general utility functions
--
----------------------------------------------------------------

local function __genSortedIndex( t )
    local sortedIndexStr = {}
    local sortedIndexInt = {}
    local sortedIndex = {}
    for key,_ in pairs(t) do
        if type(key) == 'string' then
            table.insert( sortedIndexStr, key )
        else
            table.insert( sortedIndexInt, key )
        end
    end
    table.sort( sortedIndexInt )
    table.sort( sortedIndexStr )
    for _,value in ipairs(sortedIndexInt) do
        table.insert( sortedIndex, value )
    end
    for _,value in ipairs(sortedIndexStr) do
        table.insert( sortedIndex, value )
    end
    return sortedIndex
end
M.private.__genSortedIndex = __genSortedIndex

-- Contains the keys of the table being iterated, already sorted
-- and the last index that has been iterated
-- Example:
--    t a table on which we iterate
--    sortedNextCache[ t ].idx is the sorted index of the table
--    sortedNextCache[ t ].lastIdx is the last index used in the sorted index
local sortedNextCache = {}

local function sortedNext(t, state)
    -- Equivalent of the next() function of table iteration, but returns the
    -- keys in the alphabetic order. We use a temporary sorted key table that
    -- is stored in a global variable. We also store the last index
    -- used in the iteration to find the next one quickly

    --print("sortedNext: state = "..tostring(state) )
    local key
    if state == nil then
        -- the first time, generate the index
        -- cleanup the previous index, just in case...
        sortedNextCache[ t ] = nil
        sortedNextCache[ t ] = { idx=__genSortedIndex( t ), lastIdx=1 }
        key = sortedNextCache[t].idx[1]
        return key, t[key]
    end

    -- normally, the previous index in the orderedTable is there:
    local lastIndex = sortedNextCache[ t ].lastIdx
    if sortedNextCache[t].idx[lastIndex] == state then
        key = sortedNextCache[t].idx[lastIndex+1]
        sortedNextCache[ t ].lastIdx = lastIndex+1
    else
        -- strange, we have to find the next value by ourselves
        key = nil
        for i = 1,#sortedNextCache[t] do
            if sortedNextCache[t].idx[i] == state then
                key = sortedNextCache[t].idx[i+1]
                sortedNextCache[ t ].lastIdx = i+1
                -- break
            end
        end
    end

    if key then
        return key, t[key]
    end

    -- no more value to return, cleanup
    sortedNextCache[t] = nil
    return
end
M.private.sortedNext = sortedNext

local function sortedPairs(t)
    -- Equivalent of the pairs() function on tables. Allows to iterate
    -- in sorted order. This works only if the key types are all the same
    -- and support comparison
    return sortedNext, t, nil
end

local function strsplit(delimiter, text)
-- Split text into a list consisting of the strings in text,
-- separated by strings matching delimiter (which may be a pattern).
-- example: strsplit(",%s*", "Anna, Bob, Charlie,Dolores")
    local list = {}
    local pos = 1
    if string.find("", delimiter, 1, true) then -- this would result in endless loops
        error("delimiter matches empty string!")
    end
    while 1 do
        local first, last = string.find(text, delimiter, pos, true)
        if first then -- found?
            table.insert(list, string.sub(text, pos, first-1))
            pos = last+1
        else
            table.insert(list, string.sub(text, pos))
            break
        end
    end
    return list
end
M.private.strsplit = strsplit

local function hasNewLine( s )
    -- return true if s has a newline
    return (string.find(s, '\n', 1, true) ~= nil)
end
M.private.hasNewLine = hasNewLine

local function prefixString( prefix, s )
    -- Prefix all the lines of s with prefix
    local t = strsplit('\n', s)
    return prefix..table.concat(t, '\n'..prefix)
end
M.private.prefixString = prefixString

local function strMatch(s, pattern, start, final )
    -- return true if s matches completely the pattern from index start to index end
    -- return false in every other cases
    -- if start is nil, matches from the beginning of the string
    -- if end is nil, matches to the end of the string
    start = start or 1
    final = final or string.len(s)

    local foundStart, foundEnd = string.find(s, pattern, start, false)
    if foundStart and foundStart == start and foundEnd == final then
        return true
    end
    return false -- no match
end
M.private.strMatch = strMatch

local function xmlEscape( s )
    -- Return s escaped for XML attributes
    -- escapes table:
    -- "   &quot;
    -- '   &apos;
    -- <   &lt;
    -- >   &gt;
    -- &   &amp;

    return string.gsub( s, '.', {
        ['&'] = "&amp;",
        ['"'] = "&quot;",
        ["'"] = "&apos;",
        ['<'] = "&lt;",
        ['>'] = "&gt;",
    } )
end
M.private.xmlEscape = xmlEscape

local function xmlCDataEscape( s )
    -- Return s escaped for CData section
    -- escapes: "]]>"
    return string.gsub( s, ']]>', ']]&gt;' )
end
M.private.xmlCDataEscape = xmlCDataEscape

local patternLuaunitTrace='(.*[/\\]luaunit%.lua:%d+: .*)'
local function isLuaunitInternalLine( s )
    -- return true if line of stack trace comes from inside luaunit
    -- print( 'Matching for luaunit: '..s )
    local matchStart, matchEnd, capture = string.find( s, patternLuaunitTrace )
    if matchStart then
        -- print('Match luaunit line')
        return true
    end
    return false
end

local function stripLuaunitTrace( stackTrace )
    --[[
    -- Example of  a traceback:
    <<stack traceback:
        example_with_luaunit.lua:130: in function 'test2_withFailure'
        ./luaunit.lua:1449: in function <./luaunit.lua:1449>
        [C]: in function 'xpcall'
        ./luaunit.lua:1449: in function 'protectedCall'
        ./luaunit.lua:1508: in function 'execOneFunction'
        ./luaunit.lua:1596: in function 'runSuiteByInstances'
        ./luaunit.lua:1660: in function 'runSuiteByNames'
        ./luaunit.lua:1736: in function 'runSuite'
        example_with_luaunit.lua:140: in main chunk
        [C]: in ?>>

        Other example:
    <<stack traceback:
        ./luaunit.lua:545: in function 'assertEquals'
        example_with_luaunit.lua:58: in function 'TestToto.test7'
        ./luaunit.lua:1517: in function <./luaunit.lua:1517>
        [C]: in function 'xpcall'
        ./luaunit.lua:1517: in function 'protectedCall'
        ./luaunit.lua:1578: in function 'execOneFunction'
        ./luaunit.lua:1677: in function 'runSuiteByInstances'
        ./luaunit.lua:1730: in function 'runSuiteByNames'
        ./luaunit.lua:1806: in function 'runSuite'
        example_with_luaunit.lua:140: in main chunk
        [C]: in ?>>

    <<stack traceback:
        luaunit2/example_with_luaunit.lua:124: in function 'test1_withFailure'
        luaunit2/luaunit.lua:1532: in function <luaunit2/luaunit.lua:1532>
        [C]: in function 'xpcall'
        luaunit2/luaunit.lua:1532: in function 'protectedCall'
        luaunit2/luaunit.lua:1591: in function 'execOneFunction'
        luaunit2/luaunit.lua:1679: in function 'runSuiteByInstances'
        luaunit2/luaunit.lua:1743: in function 'runSuiteByNames'
        luaunit2/luaunit.lua:1819: in function 'runSuite'
        luaunit2/example_with_luaunit.lua:140: in main chunk
        [C]: in ?>>


    -- first line is "stack traceback": KEEP
    -- next line may be luaunit line: REMOVE
    -- next lines are call in the program under testOk: REMOVE
    -- next lines are calls from luaunit to call the program under test: KEEP

    -- Strategy:
    -- keep first line
    -- remove lines that are part of luaunit
    -- kepp lines until we hit a luaunit line
    ]]

    -- print( '<<'..stackTrace..'>>' )

    local t = strsplit( '\n', stackTrace )
    -- print( prettystr(t) )

    local idx=2

    -- remove lines that are still part of luaunit
    while idx <= #t do
        if isLuaunitInternalLine( t[idx] ) then
            -- print('Removing : '..t[idx] )
            table.remove(t, idx)
        else
            break
        end
    end

    -- keep lines until we hit luaunit again
    while (idx <= #t) and (not isLuaunitInternalLine(t[idx])) do
        -- print('Keeping : '..t[idx] )
        idx = idx+1
    end

    -- remove remaining luaunit lines
    while idx <= #t do
        -- print('Removing : '..t[idx] )
        table.remove(t, idx)
    end

    -- print( prettystr(t) )
    return table.concat( t, '\n')

end
M.private.stripLuaunitTrace = stripLuaunitTrace


function table.keytostring(k)
    -- like prettystr but do not enclose with "" if the string is just alphanumerical
    -- this is better for displaying table keys who are often simple strings
    if "string" == type( k ) and string.match( k, "^[_%a][_%a%d]*$" ) then
        return k
    else
        return M.prettystr(k)
    end
end

function table.tostring( tbl, indentLevel, printTableRefs, recursionTable )
    printTableRefs = printTableRefs or M.PRINT_TABLE_REF_IN_ERROR_MSG
    recursionTable = recursionTable or {}
    recursionTable[tbl] = true

    local result, done = {}, {}
    local dispOnMultLines = false

    for k, v in ipairs( tbl ) do
        if recursionTable[v] then
            -- recursion detected!
            recursionTable['recursionDetected'] = true
            table.insert( result, "<"..tostring(v)..">" )
        else
            table.insert( result, M.private.prettystr_sub( v, indentLevel+1, false, printTableRefs, recursionTable ) )
        end

        done[ k ] = true
    end

    for k, v in sortedPairs( tbl ) do
        if not done[ k ] then
            if recursionTable[v] then
                -- recursion detected!
                recursionTable['recursionDetected'] = true
                table.insert( result, table.keytostring( k ) .. "=" .. "<"..tostring(v)..">" )
            else
                table.insert( result,
                    table.keytostring( k ) .. "=" .. M.private.prettystr_sub( v, indentLevel+1, true, printTableRefs, recursionTable ) )
            end
        end
    end
    if printTableRefs then
        table_ref = "<"..tostring(tbl).."> "
    else
        table_ref = ''
    end

    local SEP_LENGTH=2     -- ", "
    local totalLength = 0
    for k, v in ipairs( result ) do
        l = string.len( v )
        totalLength = totalLength + l
        if l > M.LINE_LENGTH-1 then
            dispOnMultLines = true
        end
    end
    -- adjust with length of separator
    totalLength = totalLength + SEP_LENGTH * math.max( 0, #result-1) + 2 -- two items need 1 sep, thee items two seps + len of '{}'
    if totalLength > M.LINE_LENGTH-1 then
        dispOnMultLines = true
    end

    if dispOnMultLines then
        indentString = string.rep("    ", indentLevel)
        closingIndentString = string.rep("    ", math.max(0, indentLevel-1) )
        result_str = table_ref.."{\n"..indentString .. table.concat( result, ",\n"..indentString  ) .. "\n"..closingIndentString.."}"
    else
        result_str = table_ref.."{".. table.concat( result, ", " ) .. "}"
    end
    return result_str
end

local function prettystr( v, keeponeline )
    --[[ Better string conversion, to display nice variable content:
    For strings, if keeponeline is set to true, string is displayed on one line, with visible \n
    * string are enclosed with " by default, or with ' if string contains a "
    * if table is a class, display class name
    * tables are expanded
    ]]--
    local recursionTable = {}
    local s = M.private.prettystr_sub(v, 1, keeponeline, M.PRINT_TABLE_REF_IN_ERROR_MSG, recursionTable)
    if recursionTable['recursionDetected'] == true and M.PRINT_TABLE_REF_IN_ERROR_MSG == false then
        -- some table contain recursive references,
        -- so we must recompute the value by including all table references
        -- else the result looks like crap
        recursionTable = {}
        s = M.private.prettystr_sub(v, 1, keeponeline, true, recursionTable)
    end
    return s
end
M.prettystr = prettystr

local function prettystr_sub(v, indentLevel, keeponeline, printTableRefs, recursionTable )
    if "string" == type( v ) then
        if keeponeline then
            v = string.gsub( v, "\n", "\\n" )
        end

        -- use clever delimiters according to content:
        -- if string contains ", enclose with '
        -- if string contains ', enclose with "
        if string.match( string.gsub(v,"[^'\"]",""), '^"+$' ) then
            return "'" .. v .. "'"
        end
        return '"' .. string.gsub(v,'"', '\\"' ) .. '"'
    end
    if type(v) == 'table' then
        --if v.__class__ then
        --    return string.gsub( tostring(v), 'table', v.__class__ )
        --end
        return table.tostring(v, indentLevel, printTableRefs, recursionTable)
    end
    return tostring(v)
end
M.private.prettystr_sub = prettystr_sub

local function _table_contains(t, element)
    if t then
        for _, value in pairs(t) do
            if type(value) == type(element) then
                if type(element) == 'table' then
                    -- if we wanted recursive items content comparison, we could use
                    -- _is_table_items_equals(v, expected) but one level of just comparing
                    -- items is sufficient
                    if M.private._is_table_equals( value, element ) then
                        return true
                    end
                else
                    if value == element then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function _is_table_items_equals(actual, expected )
    if (type(actual) == 'table') and (type(expected) == 'table') then
        for k,v in pairs(actual) do
            if not _table_contains(expected, v) then
                return false
            end
        end
        for k,v in pairs(expected) do
            if not _table_contains(actual, v) then
                return false
            end
        end
        return true
    elseif type(actual) ~= type(expected) then
        return false
    elseif actual == expected then
        return true
    end
    return false
end

local function _is_table_equals(actual, expected)
    if (type(actual) == 'table') and (type(expected) == 'table') then
        if (#actual ~= #expected) then
            return false
        end
        local k,v
        for k,v in pairs(actual) do
            if not _is_table_equals(v, expected[k]) then
                return false
            end
        end
        for k,v in pairs(expected) do
            if not _is_table_equals(v, actual[k]) then
                return false
            end
        end
        return true
    elseif type(actual) ~= type(expected) then
        return false
    elseif actual == expected then
        return true
    end
    return false
end
M.private._is_table_equals = _is_table_equals

----------------------------------------------------------------
--
--                     assertions
--
----------------------------------------------------------------

local function errorMsgEquality(actual, expected)
    local errorMsg
    if not M.ORDER_ACTUAL_EXPECTED then
        expected, actual = actual, expected
    end
    local expectedStr = prettystr(expected)
    local actualStr = prettystr(actual)
    if type(expected) == 'string' or type(expected) == 'table' then
        if hasNewLine( expectedStr..actualStr ) then
            expectedStr = '\n'..expectedStr
            actualStr = '\n'..actualStr
        end
        errorMsg = "expected: "..expectedStr.."\n"..
                         "actual: "..actualStr
    else
        errorMsg = "expected: "..expectedStr..", actual: "..actualStr
    end
    return errorMsg
end

function M.assertError(f, ...)
    -- assert that calling f with the arguments will raise an error
    -- example: assertError( f, 1, 2 ) => f(1,2) should generate an error
    local no_error, error_msg = pcall( f, ... )
    if not no_error then return end
    error( "Expected an error when calling function but no error generated", 2 )
end

function M.assertTrue(value)
    if not value then
        error("expected: true, actual: " ..prettystr(value), 2)
    end
end

function M.assertFalse(value)
    if value then
        error("expected: false, actual: " ..prettystr(value), 2)
    end
end

function M.assertNil(value)
    if value ~= nil then
        error("expected: nil, actual: " ..prettystr(value), 2)
    end
end

function M.assertNotNil(value)
    if value == nil then
        error("expected non nil value, received nil", 2)
    end
end

function M.assertEquals(actual, expected)
    if type(actual) == 'table' and type(expected) == 'table' then
        if not _is_table_equals(actual, expected) then
            error( errorMsgEquality(actual, expected), 2 )
        end
    elseif type(actual) ~= type(expected) then
        error( errorMsgEquality(actual, expected), 2 )
    elseif actual ~= expected then
        error( errorMsgEquality(actual, expected), 2 )
    end
end

function M.assertAlmostEquals( actual, expected, margin )
    -- check that two floats are close by margin
    if type(actual) ~= 'number' or type(expected) ~= 'number' or type(margin) ~= 'number' then
        error('assertAlmostEquals: must supply only number arguments.\nArguments supplied: '..actual..', '..expected..', '..margin, 2)
    end
    if margin < 0 then
        error( 'assertAlmostEquals: margin must be positive, current value is '..margin, 2)
    end

    if not M.ORDER_ACTUAL_EXPECTED then
        expected, actual = actual, expected
    end

    -- help lua in limit cases like assertAlmostEquals( 1.1, 1.0, 0.1)
    -- which by default does not work. We need to give margin a small boost
    local realmargin = margin + 0.00000000001
    if math.abs(expected - actual) > realmargin then
        error( 'Values are not almost equal\nExpected: '..expected..' with margin of '..margin..', received: '..actual, 2)
    end
end

function M.assertNotEquals(actual, expected)
    if type(actual) ~= type(expected) then
        return
    end

    local genError = false
    if type(actual) == 'table' and type(expected) == 'table' then
        if not _is_table_equals(actual, expected) then
            return
        end
        genError = true
    elseif actual == expected then
        genError = true
    end
    if genError then
        error( 'Received the not expected value: ' .. prettystr(actual), 2 )
    end
end

function M.assertNotAlmostEquals( actual, expected, margin )
    -- check that two floats are not close by margin
    if type(actual) ~= 'number' or type(expected) ~= 'number' or type(margin) ~= 'number' then
        error('assertNotAlmostEquals: must supply only number arguments.\nArguments supplied: '..actual..', '..expected..', '..margin, 2)
    end
    if margin <= 0 then
        error( 'assertNotAlmostEquals: margin must be positive, current value is '..margin, 2)
    end

    if not M.ORDER_ACTUAL_EXPECTED then
        expected, actual = actual, expected
    end

    -- help lua in limit cases like assertAlmostEquals( 1.1, 1.0, 0.1)
    -- which by default does not work. We need to give margin a small boost
    local realmargin = margin + 0.00000000001
    if math.abs(expected - actual) <= realmargin then
        error( 'Values are almost equal\nExpected: '..expected..' with a difference above margin of '..margin..', received: '..actual, 2)
    end
end

function M.assertStrContains( str, sub, useRe )
    -- this relies on lua string.find function
    -- a string always contains the empty string
    local subType
    local noUseRe = not useRe
    if string.find(str, sub, 1, noUseRe) == nil then
        if noUseRe then
            subType = 'substring'
        else
            subType = 'regexp'
        end
        local subPretty = prettystr(sub)
        local strPretty = prettystr(str)
        if hasNewLine( subPretty..strPretty ) then
            subPretty = '\n'..subPretty..'\n'
            strPretty = '\n'..strPretty
        end
        error( 'Error, '..subType..' '..subPretty..' was not found in string '..strPretty, 2)
    end
end

function M.assertStrIContains( str, sub )
    -- this relies on lua string.find function
    -- a string always contains the empty string
    local lstr, lsub, subPretty, strPretty
    lstr = string.lower(str)
    lsub = string.lower(sub)
    if string.find(lstr, lsub, 1, true) == nil then
        subPretty = prettystr(sub)
        strPretty = prettystr(str)
        if hasNewLine( subPretty..strPretty ) then
            subPretty = '\n'..subPretty..'\n'
            strPretty = '\n'..strPretty
        end
        error( 'Error, substring '..subPretty..' was not found (case insensitively) in string '..strPretty,2)
    end
end

function M.assertNotStrContains( str, sub, useRe )
    -- this relies on lua string.find function
    -- a string always contains the empty string
    local substrType
    local noUseRe = not useRe
    if string.find(str, sub, 1, noUseRe) ~= nil then
        local substrType
        if noUseRe then
            substrType = 'substring'
        else
            substrType = 'regexp'
        end
        local subPretty = prettystr(sub)
        local strPretty = prettystr(str)
        if hasNewLine( subPretty..strPretty ) then
            subPretty = '\n'..subPretty..'\n'
            strPretty = '\n'..strPretty
        end
        error( 'Error, '..substrType..' '..subPretty..' was found in string '..strPretty,2)
    end
end

function M.assertNotStrIContains( str, sub )
    -- this relies on lua string.find function
    -- a string always contains the empty string
    local lstr, lsub
    lstr = string.lower(str)
    lsub = string.lower(sub)
    if string.find(lstr, lsub, 1, true) ~= nil then
        local subPretty = prettystr(sub)
        local strPretty = prettystr(str)
        if hasNewLine( subPretty..strPretty) then
            subPretty = '\n'..subPretty..'\n'
            strPretty = '\n'..strPretty
        end
        error( 'Error, substring '..subPretty..' was found (case insensitively) in string '..strPretty,2)
    end
end

function M.assertStrMatches( str, pattern, start, final )
    -- Verify a full match for the string
    -- for a partial match, simply use assertStrContains with useRe set to true
    if not strMatch( str, pattern, start, final ) then
        local patternPretty = prettystr(pattern)
        local strPretty = prettystr(str)
        if hasNewLine( patternPretty..strPretty) then
            patternPretty = '\n'..patternPretty..'\n'
            strPretty = '\n'..strPretty
        end
        error( 'Error, pattern '..patternPretty..' was not matched by string '..strPretty,2)
    end
end

function M.assertErrorMsgEquals( expectedMsg, func, ... )
    -- assert that calling f with the arguments will raise an error
    -- example: assertError( f, 1, 2 ) => f(1,2) should generate an error
    local no_error, error_msg = pcall( func, ... )
    if no_error then
        error( 'No error generated when calling function but expected error: "'..expectedMsg..'"', 2 )
    end
    if not (error_msg == expectedMsg) then
        if hasNewLine( error_msg..expectedMsg ) then
            expectedMsg = '\n'..expectedMsg
            error_msg = '\n'..error_msg
        end
        error( 'Exact error message expected: "'..expectedMsg..'"\nError message received: "'..error_msg..'"\n',2)
    end
end

function M.assertErrorMsgContains( partialMsg, func, ... )
    -- assert that calling f with the arguments will raise an error
    -- example: assertError( f, 1, 2 ) => f(1,2) should generate an error
    local no_error, error_msg = pcall( func, ... )
    if no_error then
        error( 'No error generated when calling function but expected error containing: '..prettystr(partialMsg), 2 )
    end
    if not string.find( error_msg, partialMsg, nil, true ) then
        local partialMsgStr = prettystr(partialMsg)
        local errorMsgStr = prettystr(error_msg)
        if hasNewLine(error_msg..partialMsg) then
            partialMsgStr = '\n'..partialMsgStr
            errorMsgStr = '\n'..errorMsgStr
        end
        error( 'Error message does not contain: '..partialMsgStr..'\nError message received: '..errorMsgStr..'\n',2)
    end
end

function M.assertErrorMsgMatches( expectedMsg, func, ... )
    -- assert that calling f with the arguments will raise an error
    -- example: assertError( f, 1, 2 ) => f(1,2) should generate an error
    local no_error, error_msg = pcall( func, ... )
    if no_error then
        error( 'No error generated when calling function but expected error matching: "'..expectedMsg..'"', 2 )
    end
    if not strMatch( error_msg, expectedMsg ) then
        if hasNewLine(error_msg..expectedMsg) then
            expectedMsg = '\n'..expectedMsg
            error_msg = '\n'..error_msg
        end
        error( 'Error message does not match: "'..expectedMsg..'"\nError message received: "'..error_msg..'"\n',2)
    end
end

local function errorMsgTypeMismatch( expectedType, actual )
    local actualStr = prettystr(actual)
    if hasNewLine(actualStr) then
        actualStr =  '\n'..actualStr
    end
    return "Expected: a "..expectedType..' value, actual: type '..type(actual)..', value '..actualStr
end

function M.assertIsNumber(value)
    if type(value) ~= 'number' then
        error( errorMsgTypeMismatch( 'number', value ), 2 )
    end
end

function M.assertIsString(value)
    if type(value) ~= "string" then
        error( errorMsgTypeMismatch( 'string', value ), 2 )
    end
end

function M.assertIsTable(value)
    if type(value) ~= 'table' then
        error( errorMsgTypeMismatch( 'table', value ), 2 )
    end
end

function M.assertIsBoolean(value)
    if type(value) ~= 'boolean' then
        error( errorMsgTypeMismatch( 'boolean', value ), 2 )
    end
end

function M.assertIsNil(value)
    if type(value) ~= "nil" then
        error( errorMsgTypeMismatch( 'nil', value ), 2 )
    end
end

function M.assertIsFunction(value)
    if type(value) ~= 'function' then
        error( errorMsgTypeMismatch( 'function', value ), 2 )
    end
end

function M.assertIsUserdata(value)
    if type(value) ~= 'userdata' then
        error( errorMsgTypeMismatch( 'userdata', value ), 2 )
    end
end

function M.assertIsCoroutine(value)
    if type(value) ~= 'thread' then
        error( errorMsgTypeMismatch( 'thread', value ), 2 )
    end
end

M.assertIsThread = M.assertIsCoroutine

function M.assertIs(actual, expected)
    if not M.ORDER_ACTUAL_EXPECTED then
        actual, expected = expected, actual
    end
    if actual ~= expected then
        local expectedStr = prettystr(expected)
        local actualStr = prettystr(actual)
        if hasNewLine(expectedStr..actualStr) then
            expectedStr = '\n'..expectedStr..'\n'
            actualStr =  '\n'..actualStr
        else
            expectedStr = expectedStr..', '
        end
        error( 'Expected object and actual object are not the same\nExpected: '..expectedStr..'actual: '..actualStr, 2)
    end
end

function M.assertNotIs(actual, expected)
    if not M.ORDER_ACTUAL_EXPECTED then
        actual, expected = expected, actual
    end
    if actual == expected then
        local expectedStr = prettystr(expected)
        if hasNewLine(expectedStr) then
            expectedStr = '\n'..expectedStr
        end
        error( 'Expected object and actual object are the same object: '..expectedStr, 2 )
    end
end

function M.assertItemsEquals(actual, expected)
    -- checks that the items of table expected
    -- are contained in table actual. Warning, this function
    -- is at least O(n^2)
    if not _is_table_items_equals(actual, expected ) then
        local expectedStr = prettystr(expected)
        local actualStr = prettystr(actual)
        if hasNewLine(expectedStr..actualStr) then
            expectedStr = '\n'..expectedStr
            actualStr =  '\n'..actualStr
        end
        error( 'Contents of the tables are not identical:\nExpected: '..expectedStr..'\nActual: '..actualStr, 2 )
    end
end

M.assert_equals = M.assertEquals
M.assert_not_equals = M.assertNotEquals
M.assert_error = M.assertError
M.assert_true = M.assertTrue
M.assert_false = M.assertFalse
M.assert_is_number = M.assertIsNumber
M.assert_is_string = M.assertIsString
M.assert_is_table = M.assertIsTable
M.assert_is_boolean = M.assertIsBoolean
M.assert_is_nil = M.assertIsNil
M.assert_is_function = M.assertIsFunction
M.assert_is = M.assertIs
M.assert_not_is = M.assertNotIs


if EXPORT_ASSERT_TO_GLOBALS then
    assertError            = M.assertError
    assertTrue             = M.assertTrue
    assertFalse            = M.assertFalse
    assertNil              = M.assertNil
    assertNotNil           = M.assertNotNil
    assertEquals           = M.assertEquals
    assertAlmostEquals     = M.assertAlmostEquals
    assertNotEquals        = M.assertNotEquals
    assertNotAlmostEquals  = M.assertNotAlmostEquals
    assertStrContains      = M.assertStrContains
    assertStrIContains     = M.assertStrIContains
    assertNotStrContains   = M.assertNotStrContains
    assertNotStrIContains  = M.assertNotStrIContains
    assertStrMatches       = M.assertStrMatches
    assertErrorMsgEquals   = M.assertErrorMsgEquals
    assertErrorMsgContains = M.assertErrorMsgContains
    assertErrorMsgMatches  = M.assertErrorMsgMatches
    assertIsNumber         = M.assertIsNumber
    assertIsString         = M.assertIsString
    assertIsTable          = M.assertIsTable
    assertIsBoolean        = M.assertIsBoolean
    assertIsNil            = M.assertIsNil
    assertIsFunction       = M.assertIsFunction
    assertIsUserdata       = M.assertIsUserdata
    assertIsCoroutine      = M.assertIsCoroutine
    assertIs               = M.assertIs
    assertNotIs            = M.assertNotIs
    assertItemsEquals      = M.assertItemsEquals
    -- aliases
    assert_equals          = M.assertEquals
    assert_not_equals      = M.assertNotEquals
    assert_error           = M.assertError
    assert_true            = M.assertTrue
    assert_false           = M.assertFalse
    assert_is_number       = M.assertIsNumber
    assert_is_string       = M.assertIsString
    assert_is_table        = M.assertIsTable
    assert_is_boolean      = M.assertIsBoolean
    assert_is_nil          = M.assertIsNil
    assert_is_function     = M.assertIsFunction
    assert_is              = M.assertIs
    assert_not_is          = M.assertNotIs
end

----------------------------------------------------------------
--
--                     Outputters
--
----------------------------------------------------------------

----------------------------------------------------------------
--                     class TapOutput
----------------------------------------------------------------

local TapOutput = { -- class
    __class__ = 'TapOutput',
    runner = nil,
    result = nil,
}
local TapOutput_MT = { __index = TapOutput }

    -- For a good reference for TAP format, check: http://testanything.org/tap-specification.html

    function TapOutput:new()
        local t = {}
        t.verbosity = M.VERBOSITY_LOW
        setmetatable( t, TapOutput_MT )
        return t
    end
    function TapOutput:startSuite()
        print("1.."..self.result.testCount)
        print('# Started on '..self.result.startDate)
    end
    function TapOutput:startClass(className)
        if className ~= '[TestFunctions]' then
            print('# Starting class: '..className)
        end
    end
    function TapOutput:startTest(testName) end

    function TapOutput:addFailure( errorMsg, stackTrace )
        print(string.format("not ok %d\t%s", self.result.currentTestNumber, self.result.currentNode.testName ))
        if self.verbosity > M.VERBOSITY_LOW then
           print( prefixString( '    ', errorMsg ) )
        end
        if self.verbosity > M.VERBOSITY_DEFAULT then
           print( prefixString( '    ', stackTrace ) )
        end
    end

    function TapOutput:endTest(testHasFailure)
        if not self.result.currentNode:hasFailure() then
            print(string.format("ok     %d\t%s", self.result.currentTestNumber, self.result.currentNode.testName ))
        end
    end

    function TapOutput:endClass() end

    function TapOutput:endSuite()
        local t = {}
        table.insert(t, string.format('# Ran %d tests in %0.3f seconds, %d successes, %d failures',
            self.result.testCount, self.result.duration, self.result.testCount-self.result.failureCount, self.result.failureCount ) )
        if self.result.nonSelectedCount > 0 then
            table.insert(t, string.format(", %d non selected tests", self.result.nonSelectedCount ) )
        end
        print( table.concat(t) )
        return self.result.failureCount
    end


-- class TapOutput end

----------------------------------------------------------------
--                     class JUnitOutput
----------------------------------------------------------------

-- See directory junitxml for more information about the junit format
local JUnitOutput = { -- class
    __class__ = 'JUnitOutput',
    runner = nil,
    result = nil,
}
local JUnitOutput_MT = { __index = JUnitOutput }

    function JUnitOutput:new()
        local t = {}
        t.testList = {}
        t.verbosity = M.VERBOSITY_LOW
        t.fd = nil
        t.fname = nil
        setmetatable( t, JUnitOutput_MT )
        return t
    end
    function JUnitOutput:startSuite()

        -- open xml file early to deal with errors
        if self.fname == nil then
            error('With Junit, an output filename must be supplied with --name!')
        end
        if string.sub(self.fname,-4) ~= '.xml' then
            self.fname = self.fname..'.xml'
        end
        self.fd = io.open(self.fname, "w")
        if self.fd == nil then
            error("Could not open file for writing: "..self.fname)
        end

        print('# XML output to '..self.fname)
        print('# Started on '..self.result.startDate)
    end
    function JUnitOutput:startClass(className)
        if className ~= '[TestFunctions]' then
            print('# Starting class: '..className)
        end
    end
    function JUnitOutput:startTest(testName)
        print('# Starting test: '..testName)
    end

    function JUnitOutput:addFailure( errorMsg, stackTrace )
        print('# Failure: '..errorMsg)
        -- print('# '..stackTrace)
    end

    function JUnitOutput:endTest(testHasFailure)
    end

    function JUnitOutput:endClass()
    end

    function JUnitOutput:endSuite()
        local t = {}
        table.insert(t, string.format('# Ran %d tests in %0.3f seconds, %d successes, %d failures',
            self.result.testCount, self.result.duration, self.result.testCount-self.result.failureCount, self.result.failureCount ) )
        if self.result.nonSelectedCount > 0 then
            table.insert(t, string.format(", %d non selected tests", self.result.nonSelectedCount ) )
        end
        print( table.concat(t) )

        -- XML file writing
        self.fd:write('<?xml version="1.0" encoding="UTF-8" ?>\n')
        self.fd:write('<testsuites>\n')
        self.fd:write(string.format(
            '    <testsuite name="LuaUnit" id="00001" package="" hostname="localhost" tests="%d" timestamp="%s" time="%0.3f" errors="0" failures="%d">\n',
            self.result.testCount, self.result.startIsodate, self.result.duration, self.result.failureCount ))
        self.fd:write("        <properties>\n")
        self.fd:write(string.format('            <property name="Lua Version" value="%s"/>\n', _VERSION ) )
        self.fd:write(string.format('            <property name="LuaUnit Version" value="%s"/>\n', M.VERSION) )
        -- XXX please include system name and version if possible
        self.fd:write("        </properties>\n")

        for i,node in ipairs(self.result.tests) do
            self.fd:write(string.format('        <testcase classname="%s" name="%s" time="%0.3f">\n',
                node.className, node.testName, node.duration ) )
            if node.status ~= M.NodeStatus.PASS then
                self.fd:write('            <failure type="' ..xmlEscape(node.msg) .. '">\n')
                self.fd:write('                <![CDATA[' ..xmlCDataEscape(node.stackTrace) .. ']]></failure>\n')
            end
            self.fd:write('        </testcase>\n')

        end

        -- Next to lines are Needed to validate junit ANT xsd but really not useful in general:
        self.fd:write('    <system-out/>\n')
        self.fd:write('    <system-err/>\n')

        self.fd:write('    </testsuite>\n')
        self.fd:write('</testsuites>\n')
        self.fd:close()
        return self.result.failureCount
    end


-- class TapOutput end

----------------------------------------------------------------
--                     class TextOutput
----------------------------------------------------------------

--[[

-- Python Non verbose:

For each test: . or F or E

If some failed tests:
    ==============
    ERROR / FAILURE: TestName (testfile.testclass)
    ---------
    Stack trace


then --------------
then "Ran x tests in 0.000s"
then OK or FAILED (failures=1, error=1)

-- Python Verbose:
testname (filename.classname) ... ok
testname (filename.classname) ... FAIL
testname (filename.classname) ... ERROR

then --------------
then "Ran x tests in 0.000s"
then OK or FAILED (failures=1, error=1)

-- Ruby:
Started
 .
 Finished in 0.002695 seconds.
 
 1 tests, 2 assertions, 0 failures, 0 errors

-- Ruby:
>> ruby tc_simple_number2.rb
Loaded suite tc_simple_number2
Started
F..
Finished in 0.038617 seconds.
 
  1) Failure:
test_failure(TestSimpleNumber) [tc_simple_number2.rb:16]:
Adding doesn't work.
<3> expected but was
<4>.
 
3 tests, 4 assertions, 1 failures, 0 errors

-- Java Junit
.......F.
Time: 0,003
There was 1 failure:
1) testCapacity(junit.samples.VectorTest)junit.framework.AssertionFailedError
    at junit.samples.VectorTest.testCapacity(VectorTest.java:87)
    at sun.reflect.NativeMethodAccessorImpl.invoke0(Native Method)
    at sun.reflect.NativeMethodAccessorImpl.invoke(NativeMethodAccessorImpl.java:62)
    at sun.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)

FAILURES!!!
Tests run: 8,  Failures: 1,  Errors: 0


-- Maven

# mvn test
-------------------------------------------------------
 T E S T S
-------------------------------------------------------
Running math.AdditionTest
Tests run: 2, Failures: 1, Errors: 0, Skipped: 0, Time elapsed: 
0.03 sec <<< FAILURE!

Results :

Failed tests: 
  testLireSymbole(math.AdditionTest)

Tests run: 2, Failures: 1, Errors: 0, Skipped: 0


-- LuaUnit 
---- non verbose
* display . or F or E when running tests
---- verbose
* display test name + ok/fail
----
* blank line
* number) ERROR or FAILURE: TestName
   Stack trace
* blank line
* number) ERROR or FAILURE: TestName
   Stack trace

then --------------
then "Ran x tests in 0.000s (%d not selected, %d skipped)"
then OK or FAILED (failures=1, error=1)


]]

local TextOutput = { __class__ = 'TextOutput' }
local TextOutput_MT = { -- class
    __index = TextOutput
}

    function TextOutput:new()
        local t = {}
        t.runner = nil
        t.result = nil
        t.errorList ={}
        t.verbosity = M.VERBOSITY_DEFAULT
        setmetatable( t, TextOutput_MT )
        return t
    end

    function TextOutput:startSuite()
        if self.verbosity > M.VERBOSITY_DEFAULT then
            print( 'Started on '.. self.result.startDate )
        end
    end

    function TextOutput:startClass(className)
        -- display nothing when starting a new class
    end

    function TextOutput:startTest(testName)
        if self.verbosity > M.VERBOSITY_DEFAULT then
            io.stdout:write( "    ".. self.result.currentNode.testName.." ... " )
        end
    end

    function TextOutput:addFailure( errorMsg, stackTrace )
        -- nothing
    end

    function TextOutput:endTest(testHasFailure)
        if not testHasFailure then
            if self.verbosity > M.VERBOSITY_DEFAULT then
                io.stdout:write("Ok\n")
            else
                io.stdout:write(".")
            end
        else
            if self.verbosity > M.VERBOSITY_DEFAULT then
                io.stdout:write( 'FAIL\n' )
                print( self.result.currentNode.msg )
                --[[
                -- find out when to do this:
                if self.verbosity > M.VERBOSITY_DEFAULT then
                    print( self.result.currentNode.stackTrace )
                end
                ]]
            else
                io.stdout:write("F")
            end
        end
    end

    function TextOutput:endClass()
        -- nothing
    end

    function TextOutput:displayOneFailedTest( index, failure )
        print(index..") "..failure.testName )
        print( failure.msg )
        print( failure.stackTrace )
        print()
    end

    function TextOutput:displayFailedTests()
        if self.result.failureCount == 0 then return end
        print("Failed tests:")
        print("-------------")
        for i,v in ipairs(self.result.failures) do
            self:displayOneFailedTest( i, v )
        end
    end

    function TextOutput:endSuite()
        if self.verbosity > M.VERBOSITY_DEFAULT then
            print("=========================================================")
        else
            print()
        end
        self:displayFailedTests()
        local ignoredString = ""
        print( string.format("Ran %d tests in %0.3f seconds", self.result.testCount, self.result.duration ) )
        if self.result.failureCount == 0 then
            if self.result.nonSelectedCount > 0 then
                ignoredString = string.format('(ignored=%d)', self.result.nonSelectedCount )
            end
            print('OK '.. ignoredString)
        else
            if self.result.nonSelectedCount > 0 then
                ignoredString = ', '..ignoredString
            end
            print(string.format('FAILED (failures=%d%s)', self.result.failureCount, ignoredString ) )
        end
    end


-- class TextOutput end


----------------------------------------------------------------
--                     class NilOutput
----------------------------------------------------------------

local function nopCallable()
    --print(42)
    return nopCallable
end

local NilOutput = {
    __class__ = 'NilOuptut',
}
local NilOutput_MT = {
    __index = nopCallable,
}
function NilOutput:new()
    local t = {}
    t.__class__ = 'NilOutput'
    setmetatable( t, NilOutput_MT )
    return t
end

----------------------------------------------------------------
--
--                     class LuaUnit
--
----------------------------------------------------------------

M.LuaUnit = {
    outputType = TextOutput,
    verbosity = M.VERBOSITY_DEFAULT,
    __class__ = 'LuaUnit'
}

if EXPORT_ASSERT_TO_GLOBALS then
    LuaUnit = M.LuaUnit
end
local LuaUnit_MT = { __index = M.LuaUnit }

    function M.LuaUnit:new()
        local t = {}
        setmetatable( t, LuaUnit_MT )
        return t
    end

    -----------------[[ Utility methods ]]---------------------

    function M.LuaUnit.isFunction(aObject)
        -- return true if aObject is a function
        return 'function' == type(aObject)
    end

    function M.LuaUnit.isClassMethod(aName)
        -- return true if aName contains a class + a method name in the form class:method
        return not not string.find(aName, '.', nil, true )
    end

    function M.LuaUnit.splitClassMethod(someName)
        -- return a pair className, methodName for a name in the form class:method
        -- return nil if not a class + method name
        -- name is class + method
        local hasMethod, methodName, className
        hasMethod = string.find(someName, '.', nil, true )
        if not hasMethod then return nil end
        methodName = string.sub(someName, hasMethod+1)
        className = string.sub(someName,1,hasMethod-1)
        return className, methodName
    end

    function M.LuaUnit.isMethodTestName( s )
        -- return true is the name matches the name of a test method
        -- default rule is that is starts with 'Test' or with 'test'
        if string.sub(s,1,4):lower() == 'test' then
            return true
        end
        return false
    end

    function M.LuaUnit.isTestName( s )
        -- return true is the name matches the name of a test
        -- default rule is that is starts with 'Test' or with 'test'
        if string.sub(s,1,4):lower() == 'test' then
            return true
        end
        return false
    end

    function M.LuaUnit.collectTests()
        -- return a list of all test names in the global namespace
        -- that match LuaUnit.isTestName

        local testNames = {}
        for k, v in pairs(_G) do
            if M.LuaUnit.isTestName( k ) then
                table.insert( testNames , k )
            end
        end
        table.sort( testNames )
        return testNames
    end

    function M.LuaUnit.parseCmdLine( cmdLine )
        -- parse the command line
        -- Supported command line parameters:
        -- --verbose, -v: increase verbosity
        -- --quiet, -q: silence output
        -- --output, -o, + name: select output type
        -- --pattern, -p, + pattern: run test matching pattern, may be repeated
        -- --name, -n, + fname: name of output file for junit, default to stdout
        -- [testnames, ...]: run selected test names
        --
        -- Returns a table with the following fields:
        -- verbosity: nil, M.VERBOSITY_DEFAULT, M.VERBOSITY_QUIET, M.VERBOSITY_VERBOSE
        -- output: nil, 'tap', 'junit', 'text', 'nil'
        -- testNames: nil or a list of test names to run
        -- pattern: nil or a list of patterns

        local result = {}
        local state = nil
        local SET_OUTPUT = 1
        local SET_PATTERN = 2
        local SET_FNAME = 3

        if cmdLine == nil then
            return result
        end

        local function parseOption( option )
            if option == '--help' or option == '-h' then
                result['help'] = true
                return
            end
            if option == '--version' then
                result['version'] = true
                return
            end
            if option == '--verbose' or option == '-v' then
                result['verbosity'] = M.VERBOSITY_VERBOSE
                return
            end
            if option == '--quiet' or option == '-q' then
                result['verbosity'] = M.VERBOSITY_QUIET
                return
            end
            if option == '--output' or option == '-o' then
                state = SET_OUTPUT
                return state
            end
            if option == '--name' or option == '-n' then
                state = SET_FNAME
                return state
            end
            if option == '--pattern' or option == '-p' then
                state = SET_PATTERN
                return state
            end
            error('Unknown option: '..option,3)
        end

        local function setArg( cmdArg, state )
            if state == SET_OUTPUT then
                result['output'] = cmdArg
                return
            end
            if state == SET_FNAME then
                result['fname'] = cmdArg
                return
            end
            if state == SET_PATTERN then
                if result['pattern'] then
                    table.insert( result['pattern'], cmdArg )
                else
                    result['pattern'] = { cmdArg }
                end
                return
            end
            error('Unknown parse state: '.. state)
        end


        for i, cmdArg in ipairs(cmdLine) do
            if state ~= nil then
                setArg( cmdArg, state, result )
                state = nil
            else
                if cmdArg:sub(1,1) == '-' then
                    state = parseOption( cmdArg )
                else
                    if result['testNames'] then
                        table.insert( result['testNames'], cmdArg )
                    else
                        result['testNames'] = { cmdArg }
                    end
                end
            end
        end

        if result['help'] then
            M.LuaUnit.help()
        end

        if result['version'] then
            M.LuaUnit.version()
        end

        if state ~= nil then
            error('Missing argument after '..cmdLine[ #cmdLine ],2 )
        end

        return result
    end

    function M.LuaUnit.help()
        print(M.USAGE)
        os.exit(0)
    end

    function M.LuaUnit.version()
        print('LuaUnit v'..M.VERSION..' by Philippe Fremy <phil@freehackers.org>')
        os.exit(0)
    end

    function M.LuaUnit.patternInclude( patternFilter, expr )
        -- check if any of patternFilter is contained in expr. If so, return true.
        -- return false if None of the patterns are contained in expr
        -- if patternFilter is nil, return true (no filtering)
        if patternFilter == nil then
            return true
        end

        for i,pattern in ipairs(patternFilter) do
            if string.find(expr, pattern) then
                return true
            end
        end

        return false
    end

    --------------[[ Output methods ]]-------------------------


    local NodeStatus = { -- class
        __class__ = 'NodeStatus',
    }
    M.NodeStatus = NodeStatus
    local NodeStatus_MT = { __index = NodeStatus }

    -- values of status
    NodeStatus.PASS='PASS'
    NodeStatus.FAIL='FAIL'

    function NodeStatus:new( number, testName, className )
        local t = {}
        t.number = number
        t.testName = testName
        t.className = className
        self:pass()
        setmetatable( t, NodeStatus_MT )
        return t
    end

    function NodeStatus:pass()
        self.status = self.PASS
        -- useless but we know it's the field we want to use
        self.msg = nil
        self.stackTrace = nil
    end

    function NodeStatus:fail(msg, stackTrace)
        self.status = self.FAIL
        self.msg = msg
        self.stackTrace = stackTrace
    end

    function NodeStatus:hasFailure()
            -- print('hasFailure: '..prettystr(self))
            return (self.status ~= NodeStatus.PASS)
    end

    function M.LuaUnit:startSuite(testCount, nonSelectedCount)
        self.result = {}
        self.result.failureCount = 0
        self.result.testCount = testCount
        self.result.nonSelectedCount = nonSelectedCount
        self.result.currentTestNumber = 0
        self.result.currentClassName = ""
        self.result.currentNode = nil
        self.result.suiteStarted = true
        self.result.startTime = os.clock()
        self.result.startDate = os.date()
        self.result.startIsodate = os.date('%Y-%m-%dT%H:%M:%S')
        self.result.patternFilter = self.patternFilter
        self.result.tests = {}
        self.result.failures = {}

        self.outputType = self.outputType or TextOutput
        self.output = self.outputType:new()
        self.output.runner = self
        self.output.result = self.result
        self.output.verbosity = self.verbosity
        self.output.fname = self.fname
        self.output:startSuite()
    end

    function M.LuaUnit:startClass( className )
        self.result.currentClassName = className
        self.output:startClass( className )
    end

    function M.LuaUnit:startTest( testName  )
        self.result.currentTestNumber = self.result.currentTestNumber + 1
        self.result.currentNode = NodeStatus:new(
            self.result.currentTestNumber,
            testName,
            self.result.currentClassName
        )
        self.result.currentNode.startTime = os.clock()
        table.insert( self.result.tests, self.result.currentNode )
        self.output:startTest( testName )
    end

    function M.LuaUnit:addFailure( errorMsg, stackTrace )
        if self.result.currentNode.status == NodeStatus.PASS then
            self.result.failureCount = self.result.failureCount + 1
            self.result.currentNode:fail( errorMsg, stackTrace )
            table.insert( self.result.failures, self.result.currentNode )
        end
        self.output:addFailure( errorMsg, stackTrace )
    end

    function M.LuaUnit:endTest()
        -- print( 'endTEst() '..prettystr(self.result.currentNode))
        -- print( 'endTEst() '..prettystr(self.result.currentNode:hasFailure()))
        self.result.currentNode.duration = os.clock() - self.result.currentNode.startTime
        self.result.currentNode.startTime = nil
        self.output:endTest( self.result.currentNode:hasFailure() )
        self.result.currentNode = nil
    end

    function M.LuaUnit:endClass()
        self.output:endClass()
    end

    function M.LuaUnit:endSuite()
        if self.result.suiteStarted == false then
            error('LuaUnit:endSuite() -- suite was already ended' )
        end
        self.result.duration = os.clock()-self.result.startTime
        self.result.suiteStarted = false
        self.output:endSuite()
    end

    function M.LuaUnit:setOutputType(outputType)
        -- default to text
        -- tap produces results according to TAP format
        if outputType:upper() == "NIL" then
            self.outputType = NilOutput
            return
        end
        if outputType:upper() == "TAP" then
            self.outputType = TapOutput
            return
        end
        if outputType:upper() == "JUNIT" then
            self.outputType = JUnitOutput
            return
        end
        if outputType:upper() == "TEXT" then
            self.outputType = TextOutput
            return
        end
        error( 'No such format: '..outputType,2)
    end

    function M.LuaUnit:setVerbosity( verbosity )
        self.verbosity = verbosity
    end

    function M.LuaUnit:setFname( fname )
        self.fname = fname
    end

    --------------[[ Runner ]]-----------------

    local SPLITTER = '\n>----------<\n'

    function M.LuaUnit:protectedCall( classInstance , methodInstance, prettyFuncName)
        -- if classInstance is nil, this is just a function call
        -- else, it's method of a class being called.

        local function err_handler(e)
            return debug.traceback(e..SPLITTER, 3)
        end

        local ok, fullErrMsg, stackTrace, errMsg, t
        if classInstance then
            -- stupid Lua < 5.2 does not allow xpcall with arguments so let's use a workaround
            ok, fullErrMsg = xpcall( function () methodInstance(classInstance) end, err_handler )
        else
            ok, fullErrMsg = xpcall( function () methodInstance() end, err_handler )
        end
        if ok then
            return ok
        end

        t = strsplit( SPLITTER, fullErrMsg )
        errMsg = t[1]
        stackTrace = string.sub(t[2],2)
        if prettyFuncName then
            -- we do have the real method name, improve the stack trace
            stackTrace = string.gsub( stackTrace, "in function 'methodInstance'", "in function '"..prettyFuncName.."'")
            -- Needed for Lua 5.3
            stackTrace = string.gsub( stackTrace, "in method 'methodInstance'", "in method '"..prettyFuncName.."'")
            stackTrace = string.gsub( stackTrace, "in upvalue 'methodInstance'", "in method '"..prettyFuncName.."'")
        end

        if STRIP_LUAUNIT_FROM_STACKTRACE then
            stackTrace = stripLuaunitTrace( stackTrace )
        end

        return ok, errMsg, stackTrace
    end


    function M.LuaUnit:execOneFunction(className, methodName, classInstance, methodInstance)
        -- When executing a test function, className and classInstance must be nil
        -- When executing a class method, all parameters must be set

        local ok, errMsg, stackTrace, prettyFuncName

        if type(methodInstance) ~= 'function' then
            error( tostring(methodName)..' must be a function, not '..type(methodInstance))
        end

        if className == nil then
            className = '[TestFunctions]'
            prettyFuncName = methodName
        else
            prettyFuncName = className..'.'..methodName
        end

        if self.lastClassName ~= className then
            if self.lastClassName ~= nil then
                self:endClass()
            end
            self:startClass( className )
            self.lastClassName = className
        end

        self:startTest(prettyFuncName)

        -- run setUp first(if any)
        if classInstance and self.isFunction( classInstance.setUp ) then
            ok, errMsg, stackTrace = self:protectedCall( classInstance, classInstance.setUp, className..'.setUp')
            if not ok then
                self:addFailure( errMsg, stackTrace )
            end
        end

        -- run testMethod()
        if not self.result.currentNode:hasFailure() then
            ok, errMsg, stackTrace = self:protectedCall( classInstance, methodInstance, prettyFuncName)
            if not ok then
                self:addFailure( errMsg, stackTrace )
            end
        end

        -- lastly, run tearDown(if any)
        if classInstance and self.isFunction(classInstance.tearDown) then
            ok, errMsg, stackTrace = self:protectedCall( classInstance, classInstance.tearDown, className..'.tearDown')
            if not ok then
                self:addFailure( errMsg, stackTrace )
            end
        end

        self:endTest()
    end

    function M.LuaUnit.expandOneClass( result, className, classInstance )
        -- add all test methods of classInstance to result
        for methodName, methodInstance in sortedPairs(classInstance) do
            if M.LuaUnit.isFunction(methodInstance) and M.LuaUnit.isMethodTestName( methodName ) then
                table.insert( result, { className..'.'..methodName, classInstance } )
            end
        end
    end

    function M.LuaUnit.expandClasses( listOfNameAndInst )
        -- expand all classes (proveded as {className, classInstance}) to a list of {className.methodName, classInstance}
        -- functions and methods remain untouched
        local result = {}

        for i,v in ipairs( listOfNameAndInst ) do
            local name, instance = v[1], v[2]
            if M.LuaUnit.isFunction(instance) then
                table.insert( result, { name, instance } )
            else
                if type(instance) ~= 'table' then
                    error( 'Instance must be a table or a function, not a '..type(instance)..', value '..prettystr(instance))
                end
                if M.LuaUnit.isClassMethod( name ) then
                    className, methodName = M.LuaUnit.splitClassMethod( name )
                    methodInstance = instance[methodName]
                    if methodInstance == nil then
                        error( "Could not find method in class "..tostring(className).." for method "..tostring(methodName) )
                    end
                    table.insert( result, { name, instance } )
                else
                    M.LuaUnit.expandOneClass( result, name, instance )
                end
            end
        end

        return result
    end

    function M.LuaUnit.applyPatternFilter( patternFilter, listOfNameAndInst )
        local included = {}
        local excluded = {}

        for i,v in ipairs( listOfNameAndInst ) do
            local name, instance = v[1], v[2]

            if patternFilter and not M.LuaUnit.patternInclude( patternFilter, name ) then
                table.insert( excluded, v )
            else
                table.insert( included, v )
            end
        end
        return included, excluded

    end

    function M.LuaUnit:runSuiteByInstances( listOfNameAndInst )
        -- Run an explicit list of tests. All test instances and names must be supplied.
        -- each test must be one of:
        --   * { function name, function instance }
        --   * { class name, class instance }
        --   * { class.method name, class instance }

        local expandedList, filteredList, filteredOutList, className, methodName, methodInstance
        expandedList = self.expandClasses( listOfNameAndInst )

        filteredList, filteredOutList = self.applyPatternFilter( self.patternFilter, expandedList )

        self:startSuite( #filteredList, #filteredOutList )

        for i,v in ipairs( filteredList ) do
            local name, instance = v[1], v[2]
            if M.LuaUnit.isFunction(instance) then
                self:execOneFunction( nil, name, nil, instance )
            else
                if type(instance) ~= 'table' then
                    error( 'Instance must be a table or a function, not a '..type(instance)..', value '..prettystr(instance))
                else
                    assert( M.LuaUnit.isClassMethod( name ) )
                    className, methodName = M.LuaUnit.splitClassMethod( name )
                    methodInstance = instance[methodName]
                    if methodInstance == nil then
                        error( "Could not find method in class "..tostring(className).." for method "..tostring(methodName) )
                    end
                    self:execOneFunction( className, methodName, instance, methodInstance )
                end
            end
        end

        if self.lastClassName ~= nil then
            self:endClass()
        end

        self:endSuite()
    end

    function M.LuaUnit:runSuiteByNames( listOfName )
        -- Run an explicit list of test names

        local  className, methodName, instanceName, instance, methodInstance
        local listOfNameAndInst = {}

        for i,name in ipairs( listOfName ) do
            if M.LuaUnit.isClassMethod( name ) then
                className, methodName = M.LuaUnit.splitClassMethod( name )
                instanceName = className
                instance = _G[instanceName]

                if instance == nil then
                    error( "No such name in global space: "..instanceName )
                end

                if type(instance) ~= 'table' then
                    error( 'Instance of '..instanceName..' must be a table, not '..type(instance))
                end

                methodInstance = instance[methodName]
                if methodInstance == nil then
                    error( "Could not find method in class "..tostring(className).." for method "..tostring(methodName) )
                end

            else
                -- for functions and classes
                instanceName = name
                instance = _G[instanceName]
            end

            if instance == nil then
                error( "No such name in global space: "..instanceName )
            end

            if (type(instance) ~= 'table' and type(instance) ~= 'function') then
                error( 'Name must match a function or a table: '..instanceName )
            end

            table.insert( listOfNameAndInst, { name, instance } )
        end

        self:runSuiteByInstances( listOfNameAndInst )
    end

    function M.LuaUnit.run(...)
        -- Run some specific test classes.
        -- If no arguments are passed, run the class names specified on the
        -- command line. If no class name is specified on the command line
        -- run all classes whose name starts with 'Test'
        --
        -- If arguments are passed, they must be strings of the class names
        -- that you want to run or generic command line arguments (-o, -p, -v, ...)

        local runner = M.LuaUnit.new()
        return runner:runSuite(...)
    end

    function M.LuaUnit:runSuite( ... )

        local args={...};
        if args[1] ~= nil and type(args[1]) == 'table' and args[1].__class__ == 'LuaUnit' then
            -- run was called with the syntax M.LuaUnit:runSuite()
            -- we support both M.LuaUnit.run() and M.LuaUnit:run()
            -- strip out the first argument
            table.remove(args,1)
        end

        if #args == 0 then
            args = cmdline_argv
        end

        local no_error, error_msg, options, val
        no_error, val = pcall( M.LuaUnit.parseCmdLine, args )
        if not no_error then
            error_msg = val
            print(error_msg)
            print()
            print(M.USAGE)
            os.exit(-1)
        end

        options = val

        if options.verbosity then
            self:setVerbosity( options.verbosity )
        end

        if options.output and options.output:lower() == 'junit' and options.fname == nil then
            print('With junit output, a filename must be supplied with -n or --name')
            os.exit(-1)
        end

        if options.output then
            no_error, val = pcall(self.setOutputType,self,options.output)
            if not no_error then
                error_msg = val
                print(error_msg)
                print()
                print(M.USAGE)
                os.exit(-1)
            end
        end

        if options.fname then
            self:setFname( options.fname )
        end

        if options.pattern then
            self.patternFilter = options.pattern
        end

        local testNames = options['testNames']

        if testNames == nil then
            testNames = M.LuaUnit.collectTests()
        end

        self:runSuiteByNames( testNames )

        return self.result.failureCount
    end

-- class LuaUnit

return M
