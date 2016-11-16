-- LuaJIT FFI wrapper over libssh (http://libssh.org/).
-- It's licensed as LGPLv2.1 (see http://git.libssh.org/projects/libssh.git/tree/COPYING).
local ffi = require("ffi")

ffi.cdef[[
typedef struct ssh_session_struct* ssh_session;
typedef struct ssh_channel_struct* ssh_channel;

ssh_session ssh_new(void);
int ssh_options_set(ssh_session session, int type, const void* value);
void ssh_free (ssh_session session);
int ssh_connect (ssh_session session);
void ssh_disconnect (ssh_session session);
int ssh_is_server_known (ssh_session session);
int ssh_is_connected (ssh_session session);
int ssh_write_knownhost (ssh_session session);
int ssh_userauth_password (ssh_session session, const char *username, const char *password);
char* ssh_get_issue_banner(ssh_session session);

ssh_channel ssh_channel_new(ssh_session session);
int ssh_channel_open_session(ssh_channel channel);
int ssh_channel_get_exit_status(ssh_channel channel);
int ssh_channel_close(ssh_channel channel);
void ssh_channel_free(ssh_channel channel);
int ssh_channel_request_exec (ssh_channel channel, const char * cmd);
int ssh_channel_read(ssh_channel channel, void *dest, uint32_t count, int is_stderr);
int ssh_channel_read_nonblocking(ssh_channel channel, void *dest, uint32_t count, int is_stderr);
int ssh_channel_send_eof(ssh_channel channel);
const char* ssh_get_error (void * error);
typedef struct ssh_private_key_struct* ssh_private_key;
typedef struct ssh_public_key_struct* ssh_public_key;
typedef struct ssh_key_struct* ssh_key;
typedef struct ssh_string_struct* ssh_string;

int ssh_userauth_autopubkey(ssh_session session, const char *passphrase);
int ssh_userauth_pubkey(ssh_session session, const char *username, ssh_string publickey, ssh_private_key privatekey);
int ssh_userauth_privatekey_file(ssh_session session, const char *username,
    const char *filename, const char *passphrase);
const char *ssh_version(int req_version);

int usleep(unsigned int sec);
]]

local libssh = ffi.load("ssh")
local low_version = 5 * 2^8 + 2
assert(libssh.ssh_version(ffi.new("int", low_version)), "Your libssh is too old! At least 0.5.2 is required.")

local function int_to_num(i)
    return ffi.new("int[1]", i)
end

-- Debug stub.
local function debug(s)
    print (s)
end

local c = {
    -- enum ssh_auth_e
    SSH_AUTH_SUCCESS = 0,
    SSH_AUTH_DENIED = 1,
    SSH_AUTH_PARTIAL = 2,
    SSH_AUTH_INFO = 3,
    SSH_AUTH_AGAIN = 4,
    SSH_AUTH_ERROR = -1,
    
    -- enum ssh_server_known_e
    SSH_SERVER_ERROR = -1,
    SSH_SERVER_NOT_KNOWN = 0,
    SSH_SERVER_KNOWN_OK = 1,
    SSH_SERVER_KNOWN_CHANGED = 2,
    SSH_SERVER_FOUND_OTHER = 3,
    SSH_SERVER_FILE_NOT_FOUND = 4,
}

local function check_auth_status(ssh_status)
    if ssh_status == c.SSH_AUTH_SUCCESS then
        return true, "ok"
    elseif ssh_status == c.SSH_AUTH_PARTIAL then
        return true, "partial"
    else
        -- local err = libssh.ssh_get_error(session)
        -- debug (ffi.string(err))
        return nil, string.format("Authentication failed with status %d.", ssh_status)
    end
end

-- Creates session.
-- @return session libssh session
local function new()
    -- Initialize session
    local session = libssh.ssh_new()
    -- Check if everything is ok
    if session == nil then
        return nil, "Cannot create session"
    end
    return session
end

-- Connects to the server.
-- @param session
-- @param strict_host_key_checking
local function connect(session, strict_host_key_checking)
    assert(session ~= nil, "Session shouldn't be nil")
    -- Connecting to the server
    if libssh.ssh_connect(session) ~= c.SSH_AUTH_SUCCESS then
        return nil, "Unable to connect"
    end
    -- Verifying hosts file
    known_status = libssh.ssh_is_server_known(session)
    if known_status ~= c.SSH_SERVER_KNOWN_OK then
        if (strict_host_key_checking) then
            return nil, "Host is unknown"
        elseif (known_status == c.SSH_SERVER_NOT_KNOWN or
              known_status == c.SSH_SERVER_FILE_NOT_FOUND) then
            debug("unknown host: adding...")
            libssh.ssh_write_knownhost(session)
        else
            -- TODO: return proper human-readable explaination
            return nil, "Failed checking known hosts!"
        end
    end
    return true
end


-- Performs password authentication.
-- @param session
-- @param password
local function auth_password(session, password)
    assert(session ~= nil, "Session shouldn't be nil")
    if (type(password) ~= "string") then
        return nil, "Password should be string"
    end
    local auth_status = libssh.ssh_userauth_password(session, nil, password)
    return check_auth_status(auth_status)
end

-- Performs authentication by public keys in ~/.ssh directory.
-- @param session
-- @param password public key password
local function auth_autopubkey(session, password)
    assert(session ~= nil, "Session shouldn't be nil")
    if (type(password) ~= "string" and password ~= nil) then
        return nil, "Password should be string"
    end
    local auth_status = libssh.ssh_userauth_autopubkey(session, password)
    return check_auth_status(auth_status)
end

-- TODO: auth_publickey_file and auth_gssapi

-- Sets particular option.
-- @param session libssh session
-- @param option option to set
-- @param value option value
-- @return ok, reason
local function set_option(session, option, value)
    assert(session ~= nil, "Session shouldn't be nil")
    if option == "host" then
        assert(type(value) == "string", "host must be string")
        return (libssh.ssh_options_set(session, 0, value) >= 0)
    elseif option == "port" then
        assert(type(value) == "number", "port must be integer")
        return (libssh.ssh_options_set(session, 1, int_to_num(value)) >= 0)
    elseif option == "user" then
        assert(type(value) == "string", "user must be string")
        return (libssh.ssh_options_set(session, 4, value) >= 0)
    elseif option == "ssh_dir" then
        assert(type(value) == "string", "ssh_dir must be string")
        return (libssh.ssh_options_set(session, 5, value) >= 0)
    elseif option == "identity" then
        assert(type(value) == "string", "identity must be string")
        return (libssh.ssh_options_set(session, 6, value) >= 0)
    elseif option == "known_hosts" then
        assert(type(value) == "string", "known_hosts must be string")
        return (libssh.ssh_options_set(session, 8, value) >= 0)
    elseif option == "timeout" then
        assert(type(value) == "number", "Timeout must be number")
        return (libssh.ssh_options_set(session, 9, int_to_num(value)) >= 0)
    elseif option == "ssh1" then
        assert(type(value) == "boolean", "ssh1 must be boolean")
        return (libssh.ssh_options_set(session, 11, int_to_num(value and 1 or 0)) >= 0)
    elseif option == "ssh2" then
        assert(type(value) == "boolean", "ssh2 must be boolean")
        return (libssh.ssh_options_set(session, 12, int_to_num(value and 1 or 0)) >= 0)
    elseif option == "strict_hostkey" then
        assert(type(value) == "boolean", "strict_hostkey must be boolean")
        return (libssh.ssh_options_set(session, 21, int_to_num(value and 1 or 0)) >= 0)
    else
        return nil, "Not implemented"
    end
    return nil, "Unknown option"
end

-- close the connection and free memory
local function close(session)
    assert(session ~= nil, "Session shouldn't be nil")
    if libssh.ssh_is_connected(session) then
        libssh.ssh_disconnect(session)
    end
    libssh.ssh_free(session)
    return true
end

local function get_issue_banner(session)
    assert(session ~= nil, "Session shouldn't be nil")
    return libssh.ssh_get_issue_banner(session)
end

local function request_exec(session, cmd, callback)
    assert(session ~= nil, "Session shouldn't be nil")
    assert(type(cmd) == "string")
    local channel = libssh.ssh_channel_new(session)
    if channel == nil then
        return nil, "Unable to create channel"
    end
    local rc = libssh.ssh_channel_open_session(channel);
    if rc ~= 0 then
        libssh.ssh_channel_free(channel);
        return nil, "Unable to open channel session"
    end
    
    -- TODO: retreive exit code
    local rc = libssh.ssh_channel_request_exec(channel, cmd)
    if rc ~= 0 then
        -- err = libssh.ssh_get_error(session)
        -- debug (ffi.string(err))
        libssh.ssh_channel_close(channel);
        libssh.ssh_channel_free(channel);
        return nil, "Unable to perform request."
    end
    local chunks = {}
    local buffer = ffi.new("char[1024]", {})
    local nbytes = libssh.ssh_channel_read(channel, buffer, 1024, 0);
    while nbytes > 0 do
        local s = ffi.string(buffer, nbytes)
        if callback then
            callback(s)
        else
            table.insert(chunks, s)
        end
        nbytes = libssh.ssh_channel_read(channel, buffer, 1024, 0);
    end
    
    if nbytes < 0 then
        libssh.ssh_channel_close(channel);
        libssh.ssh_channel_free(channel);
        return nil
    end
    libssh.ssh_channel_send_eof(channel)
    libssh.ssh_channel_close(channel)
    local rc
    local ctr = 0
    repeat
        ffi.C.usleep(50000)
        rc = libssh.ssh_channel_get_exit_status(channel)
        ctr = ctr + 1
    until rc ~= -1 or ctr > 20
    libssh.ssh_channel_free(channel)
    if callback then
        return true, rc
    else
        return table.concat(chunks), rc
    end
end

return {
    new = new,
    connect = connect,
    auth_password = auth_password,
    auth_autopubkey = auth_autopubkey,
    set_option = set_option,
    close = close,
    get_issue_banner = get_issue_banner,
    request_exec = request_exec,
}
