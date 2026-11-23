#include <bsm/audit.h>
#include <errno.h>
#include <stdint.h>

// Unprivileged read. The caller records errno if the OS declines the query.
static inline int RiftletReadAuditSession(pid_t pid, uint32_t *user, uint32_t *session) {
    auditpinfo_addr_t record = { 0 };
    record.ap_pid = pid;
    if (auditon(A_GETPINFO_ADDR, &record, sizeof(record)) != 0) return errno;
    if (record.ap_pid != pid || record.ap_asid == 0 || record.ap_auid == (au_id_t)-1) return EINVAL;
    *user = record.ap_auid;
    *session = record.ap_asid;
    return 0;
}
