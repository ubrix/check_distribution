# check_distribution
Just a hack to check distribution of scheduled checks in OP5 Monitor

Prerequisite:
`yum install perl perl-Statistics-Basic perl-Statistics-Descriptive`

Check distribution:
`perl ~jsundeen/check_distribution_of_checks.pl -q`

Force redistribution:
`perl ~jsundeen/mon_redistribute_next_check.pl -f`
