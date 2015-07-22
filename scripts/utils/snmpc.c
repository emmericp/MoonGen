#include <stdlib.h>

#include <arpa/inet.h>

#include <net-snmp/net-snmp-config.h>
#include <net-snmp/net-snmp-includes.h>

#include <lualib.h>
#include <lua.h>
#include <lauxlib.h>

#define MAX_OID_STR_LEN 512
#define MAX_IP_OID_LEN (2 + 3 + 4*16) // 2 for "<ipVersion>.", 3 for "<bytes>." 4*16 for each byte "<bytevalue>."
#define SNMP_ADDR_IPV6 2
#define SNMP_ADDR_IPV4 1
#define BUF_LEN 1024

typedef struct snmp_session *session_userdata_t;

/*
 * TODO: V3 auth
 * snmp.openSession(peername, version, ...)
 *
 */
static int l_session_open(lua_State *L) {
    struct snmp_session s, *session;
    session_userdata_t *su;
    size_t len;
    char *peername, *commstr, *sec_name, *auth_passphrase, *enc_passphrase;
    int version, sec_level, auth_proto;
    
    peername = (char *) luaL_checklstring(L, 1, &len);
    if (len < 1) {
        luaL_error(L, "peername cannot be empty");
    }
    
    version = luaL_checkinteger(L, 2);
    
    session = &s;
    snmp_sess_init(session);
    session->peername = peername;
    session->version = version;
    
    if ( version == SNMP_VERSION_3 ) {
        /*
         * TODO if needed
         */
        luaL_error(L, "snmp.version3 not supported yet");
        /*
         * Suppress compilewarnings about unused variables
         */
        (void) sec_name;
        (void) auth_passphrase;
        (void) enc_passphrase;
        (void) sec_level;
        (void) auth_proto;
    } else {
        /*
         * Version 1 and 2c
         */
        commstr = (char *) luaL_checklstring(L, 3, &len);
        if (len < 1) {
            luaL_error(L, "community cannot be empty");
        }
        session->community = (u_char *) commstr;
        session->community_len = strlen(commstr);
    }
    
    su = (session_userdata_t *) lua_newuserdata(L, sizeof(session_userdata_t));
    *su = NULL;
    
    luaL_getmetatable(L, "snmpSession");
    lua_setmetatable(L, -2);
    
    session = snmp_open(session);
    *su = session;
    
    return session != NULL;
}

/*
 * session:get(string oid)
 * @return table { "name": value (str), ...}
 */
static int l_session_get(lua_State *L) {
    int ret;
    size_t len;
    const char *oid_str = luaL_checklstring(L, 2, &len);
    if (len < 1) {
        luaL_error(L, "oid cannot be empty\n");
    }
    struct snmp_session *session = *((session_userdata_t *) luaL_checkudata(L, 1, "snmpSession"));
    
    struct snmp_pdu *request, *response;
    oid req_oid[(len = MAX_OID_LEN)];
    struct variable_list *vars;
    
    ret = get_node(oid_str, req_oid, &len);
    if (!ret) {
        luaL_error(L, "cannot parse oid %s\n", oid_str);
    }
    request = snmp_pdu_create(SNMP_MSG_GET);
    snmp_add_null_var(request, req_oid, len);
    
    ret = snmp_synch_response(session, request, &response);
    if (ret == STAT_SUCCESS && response->errstat == SNMP_ERR_NOERROR) {
        char buffer[BUF_LEN];
        lua_newtable(L);
        for (vars = response->variables; vars; vars = vars->next_variable) {
            //TODO: return with appropriate datatypes
            snprint_objid(buffer, BUF_LEN, vars->name, vars->name_length);
            lua_pushstring(L, buffer);
            snprint_value(buffer, BUF_LEN, vars->name, vars->name_length, vars);
            lua_pushstring(L, buffer);
            lua_settable(L, -3);
        }
    } else {
        if (ret == STAT_SUCCESS) {
            fprintf(stderr, "Error in packet: %s\n", snmp_errstring(response->errstat));
        } else {
            fprintf(stderr, "Session error: %s\n", snmp_errstring(ret));
        }
    }
    
    if (response) {
        snmp_free_pdu(response);
    }
    return ret == STAT_SUCCESS;
}

static char *ip2oid(char *ip, char *dst, size_t maxlen) {
    if (strchr(ip, '.') != NULL) {
        //IPV4
        //NOTE: a simple copy should be enough here
        unsigned char buf[4];
        inet_pton(AF_INET, ip, buf);
        snprintf(dst, maxlen, "%u.4.%u.%u.%u.%u", SNMP_ADDR_IPV4, buf[0], buf[1], buf[2], buf[3]);
    } else {
        //IPV6
        unsigned char buf[16];
        //transform to binary form, so i dont have to care about left out zeros
        inet_pton(AF_INET6, ip, buf);
        snprintf(dst, maxlen, "%u.16.%u.%u.%u.%u.%u.%u.%u.%u.%u.%u.%u.%u.%u.%u.%u.%u", SNMP_ADDR_IPV6,
                 buf[0], buf[1], buf[2], buf[3], buf[4], buf[5], buf[6], buf[7], buf[8], buf[9], buf[10],
                 buf[11], buf[12], buf[13], buf[14], buf[15]);
    }
    return dst;
}


/*
 * session:set({oid: string, type: string, value: string}, ...)
 *
 *
 *
 * @return 0 - failed, 1 success
 */
static int l_session_set(lua_State *L) {
    //TODO:
    luaL_error(L, "not implemented, yet\n");
    return 1;
}

/*
 * session:addRouteEntry(destIp, pfx, nextHopIp, iface, type, metric)
 */
static int l_session_add_route_entry(lua_State *L) {
    int integer_var_value;
    unsigned long ulong_var_value;
    
    char oid_str[MAX_OID_STR_LEN];
    struct snmp_pdu *request, *response;
    //oid stack space is reusable as it is copied when creating a new variable
    size_t oid_len = MAX_OID_LEN;
    oid req_oid[oid_len];
    struct variable_list *vars;
    
    struct snmp_session *session = *((session_userdata_t *) luaL_checkudata(L, 1, "snmpSession"));
    char *dst = luaL_checkstring(L, 2);
    int pfx = luaL_checkinteger(L, 3);
    char *next_hop = luaL_checkstring(L, 4);
    int iface = luaL_checkinteger(L, 5);
    int type = luaL_checkinteger(L, 6);
    int valid_metric;
    int metric = lua_tointegerx(L, 7, &valid_metric);
    
    char dst_buf[MAX_IP_OID_LEN], next_buf[MAX_IP_OID_LEN];
    ip2oid(dst, dst_buf, MAX_IP_OID_LEN);
    ip2oid(next_hop, next_buf, MAX_IP_OID_LEN);
    
    request = snmp_pdu_create(SNMP_MSG_SET);
    
    // in following OIDs "2.0.0" is the inetCidrRoutePolicy which should default to the oid { 0 0 }
    // it is used to distinguish between route to the same destination and next hop (but different interfaces)
    
    // set inetCidrRouteStatus to 4 which means CreateAndGo
    snprintf(oid_str, MAX_OID_STR_LEN, "IP-FORWARD-MIB::inetCidrRouteStatus.%s.%i.2.0.0.%s", dst_buf,
             pfx, next_buf);
    printf("%s i 4\n", oid_str);
    integer_var_value = 4;
    oid_len = MAX_OID_LEN;
    read_objid(oid_str, req_oid, &oid_len);
    snmp_pdu_add_variable(request, req_oid, oid_len, ASN_INTEGER, &integer_var_value,
                          sizeof(integer_var_value));
    
    // set interface of this route
    snprintf(oid_str, MAX_OID_STR_LEN, "IP-FORWARD-MIB::inetCidrRouteIfIndex.%s.%i.2.0.0.%s", dst_buf,
             pfx, next_buf);
    printf("%s i %d\n", oid_str, iface);
    oid_len = MAX_OID_LEN;
    read_objid(oid_str, req_oid, &oid_len);
    snmp_pdu_add_variable(request, req_oid, oid_len, ASN_INTEGER, &iface, sizeof(iface));
    
    // set route type
    snprintf(oid_str, MAX_OID_STR_LEN, "IP-FORWARD-MIB::inetCidrRouteType.%s.%i.2.0.0.%s", dst_buf,
             pfx, next_buf);
    printf("%s i %d\n", oid_str, type);
    oid_len = MAX_OID_LEN;
    read_objid(oid_str, req_oid, &oid_len);
    snmp_pdu_add_variable(request, req_oid, oid_len, ASN_INTEGER, &type, sizeof(type));
    
    // set nextHop AS to zero (unkown/irrelevant)
    snprintf(oid_str, MAX_OID_STR_LEN, "IP-FORWARD-MIB::inetCidrRouteNextHopAS.%s.%i.2.0.0.%s", dst_buf,
             pfx, next_buf);
    printf("%s u 0\n", oid_str);
    ulong_var_value = 0;
    oid_len = MAX_OID_LEN;
    read_objid(oid_str, req_oid, &oid_len);
    snmp_pdu_add_variable(request, req_oid, oid_len, ASN_GAUGE, &ulong_var_value,
                          sizeof(ulong_var_value));
    
    // set metric to given or -1 (unused)
    snprintf(oid_str, MAX_OID_STR_LEN, "IP-FORWARD-MIB::inetCidrRouteMetric1.%s.%i.2.0.0.%s", dst_buf,
             pfx, next_buf);
    metric = valid_metric ? metric : -1;
    printf("%s i %d\n", oid_str, metric);
    oid_len = MAX_OID_LEN;
    read_objid(oid_str, req_oid, &oid_len);
    snmp_pdu_add_variable(request, req_oid, oid_len, ASN_INTEGER, &metric, sizeof(metric));
    
    int ret = snmp_synch_response(session, request, &response);
    if (ret == STAT_SUCCESS && response->errstat == SNMP_ERR_NOERROR) {
        for (vars = response->variables; vars; vars = vars->next_variable) {
            print_variable(vars->name, vars->name_length, vars);
        }
    } else {
        if (ret == STAT_SUCCESS) {
            fprintf(stderr, "Error in packet: %s\n", snmp_errstring(response->errstat));
        } else {
            fprintf(stderr, "Session error: %s\n", snmp_errstring(ret));
        }
    }
    if (response) {
        snmp_free_pdu(response);
    }
    return ret == STAT_SUCCESS;
}

/*
 * session:deleteRouteEntry(destIp, pfx, nextHopIp)
 *
 */

static int l_session_delete_route_entry(lua_State *L) {
    char oid_str[MAX_OID_STR_LEN], dst_buf[MAX_IP_OID_LEN], next_buf[MAX_IP_OID_LEN];
    size_t oid_len = MAX_OID_LEN;
    struct snmp_pdu *request, *response;
    oid req_oid[oid_len];
    struct variable_list *vars;
    
    struct snmp_session *session = *((session_userdata_t *) luaL_checkudata(L, 1, "snmpSession"));
    unsigned int pfx = luaL_checkinteger(L, 3);
    ip2oid((char*) luaL_checkstring(L, 2), dst_buf, MAX_IP_OID_LEN);
    ip2oid((char*) luaL_checkstring(L, 4), next_buf, MAX_IP_OID_LEN);
    
    // 2.0.0 is the inetCidrRoutePolicy which should default to the oid { 0 0 }
    snprintf(oid_str, MAX_OID_STR_LEN, "IP-FORWARD-MIB::inetCidrRouteStatus.%s.%u.2.0.0.%s", dst_buf,
             pfx, next_buf);
    
    request = snmp_pdu_create(SNMP_MSG_SET);
    int value = 6; //SNMP STATUS DESTROY
    read_objid(oid_str, req_oid, &oid_len);
    snmp_pdu_add_variable(request, req_oid, oid_len, ASN_INTEGER, &value, sizeof(value));
    
    int ret = snmp_synch_response(session, request, &response);
    if (ret == STAT_SUCCESS && response->errstat == SNMP_ERR_NOERROR) {
        for (vars = response->variables; vars; vars = vars->next_variable) {
            print_variable(vars->name, vars->name_length, vars);
        }
    } else {
        if (ret == STAT_SUCCESS) {
            ret = response->errstat;
            fprintf(stderr, "Error in packet: %s\n", snmp_errstring(ret));
        } else {
            fprintf(stderr, "Session error: %s\n", snmp_errstring(ret));
        }
    }
    if (response) {
        snmp_free_pdu(response);
    }
    return ret == STAT_SUCCESS;
}

/*
 * session:addIp(ip, pfx, if_id)
 */
static int l_session_add_ip(lua_State *L) {
    char oid_str[MAX_OID_STR_LEN], ip_buf[MAX_IP_OID_LEN];
    size_t oid_len = MAX_OID_LEN, prefix_oid_len = MAX_OID_LEN;
    struct snmp_pdu *request, *response;
    oid req_oid[oid_len], prefix[prefix_oid_len];
    struct variable_list *vars;
    
    struct snmp_session *session = *((session_userdata_t *) luaL_checkudata(L, 1, "snmpSession"));
    ip2oid((char*) luaL_checkstring(L, 2), ip_buf, MAX_IP_OID_LEN);
    int pfx = luaL_checkinteger(L, 3);
    int if_id = luaL_checkinteger(L, 4);
    
    //TODO set prefix addr in prefix table
    //suppress unused warning
    (void) pfx;
    
    request = snmp_pdu_create(SNMP_MSG_SET);
    
    snprintf(oid_str, MAX_OID_STR_LEN, "IP-MIB::iAddressRowStatus.%s", ip_buf);
    int value = 4; //SNMP STATUS CREATE AND GO
    read_objid(oid_str, req_oid, &oid_len);
    snmp_pdu_add_variable(request, req_oid, oid_len, ASN_INTEGER, &value, sizeof(value));
    
    snprintf(oid_str, MAX_OID_STR_LEN, "IP-MIB::iAddressIfIndex.%s", ip_buf);
    oid_len = MAX_OID_LEN;
    read_objid(oid_str, req_oid, &oid_len);
    snmp_pdu_add_variable(request, req_oid, oid_len, ASN_INTEGER, &if_id, sizeof(if_id));
    
    snprintf(oid_str, MAX_OID_STR_LEN, "IP-MIB::iAddressStatus.%s", ip_buf);
    read_objid(oid_str, req_oid, &oid_len);
    value = 1; //PREFERRED
    snmp_pdu_add_variable(request, req_oid, oid_len, ASN_INTEGER, &value, sizeof(value));
    
    snprintf(oid_str, MAX_OID_STR_LEN, "IP-MIB::iAddressPrefix.%s", ip_buf);
    read_objid(oid_str, req_oid, &oid_len);
    //NOTE workaround until oid of prefix entry got
    prefix_oid_len = 2;
    snmp_pdu_add_variable(request, req_oid, oid_len, ASN_OBJECT_ID, &prefix, prefix_oid_len);
    
    //TODO add broadcast address
    
    int ret = snmp_synch_response(session, request, &response);
    if (ret == STAT_SUCCESS && response->errstat == SNMP_ERR_NOERROR) {
        for (vars = response->variables; vars; vars = vars->next_variable) {
            print_variable(vars->name, vars->name_length, vars);
        }
    } else {
        if (ret == STAT_SUCCESS) {
            ret = response->errstat;
            fprintf(stderr, "Error in packet: %s\n", snmp_errstring(ret));
        } else {
            fprintf(stderr, "Session error: %s\n", snmp_errstring(ret));
        }
    }
    if (response) {
        snmp_free_pdu(response);
    }
    return ret == STAT_SUCCESS;
}

/*
 * delIp(ip)
 */
static int l_session_del_ip(lua_State *L) {
    char oid_str[MAX_OID_STR_LEN], ip_buf[MAX_IP_OID_LEN];
    size_t oid_len = MAX_OID_LEN;
    struct snmp_pdu *request, *response;
    oid req_oid[oid_len];
    struct variable_list *vars;
    
    struct snmp_session *session = *((session_userdata_t *) luaL_checkudata(L, 1, "snmpSession"));
    ip2oid((char*) luaL_checkstring(L, 2), ip_buf, MAX_IP_OID_LEN);
    
    request = snmp_pdu_create(SNMP_MSG_SET);
    
    snprintf(oid_str, MAX_OID_STR_LEN, "IP-MIB::iAddressRowStatus.%s", ip_buf);
    int value = 6; //SNMP STATUS DESTROY
    read_objid(oid_str, req_oid, &oid_len);
    snmp_pdu_add_variable(request, req_oid, oid_len, ASN_INTEGER, &value, sizeof(value));
    
    int ret = snmp_synch_response(session, request, &response);
    if (ret == STAT_SUCCESS && response->errstat == SNMP_ERR_NOERROR) {
        for (vars = response->variables; vars; vars = vars->next_variable) {
            print_variable(vars->name, vars->name_length, vars);
        }
    } else {
        if (ret == STAT_SUCCESS) {
            ret = response->errstat;
            fprintf(stderr, "Error in packet: %s\n", snmp_errstring(ret));
        } else {
            fprintf(stderr, "Session error: %s\n", snmp_errstring(ret));
        }
    }
    if (response) {
        snmp_free_pdu(response);
    }
    return ret == STAT_SUCCESS;
}

static int l_session_close(lua_State *L) {
    session_userdata_t *su = (session_userdata_t *) luaL_checkudata(L, 1, "snmpSession");
    return snmp_close(*su);
}

static const struct luaL_Reg session_functions[] = {
    {"__gc", l_session_close},
    {"get", l_session_get},
    {"set", l_session_set},
    {"deleteRouteEntry", l_session_delete_route_entry},
    {"addRouteEntry", l_session_add_route_entry},
    {"addIp", l_session_add_ip},
    {"delIp", l_session_del_ip},
    {NULL, NULL}
};

static const struct luaL_Reg snmp_functions[] = {
    { "session", l_session_open},
    { NULL, NULL}
};

static int push_asn_types_table(lua_State *L) {
    lua_newtable(L);
    return 1;
}

int luaopen_snmp(lua_State *L) {
    /*
     * session = {}
     * session.__index = session
     */
    luaL_newmetatable(L, "snmpSession");
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
    luaL_setfuncs(L, session_functions, 0);
    
    init_snmp("lua_snmp");
    luaL_newlib(L, snmp_functions);
    
    push_asn_types_table(L);
    lua_setfield(L, -2, "types");
    
    //declare snmp versions
    lua_pushinteger(L, SNMP_VERSION_1);
    lua_setfield(L, -2, "version1");
    lua_pushinteger(L, SNMP_VERSION_2c);
    lua_setfield(L, -2, "version2c");
    lua_pushinteger(L, SNMP_VERSION_3);
    lua_setfield(L, -2, "version3");
    
    //declare snmp auth vars
    
    return 1;
}
