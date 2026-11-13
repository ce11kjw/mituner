BEGIN { FS="|"; printf "[" }
FILENAME ~ /pm\.txt$/ { sub(/^package:/,""); inst[$0]=1; next }
FILENAME ~ /games\.db$/ && NF>=3 {
  id=$1; nm=$2; pk=$3
  ins = (pk in inst) ? "true" : "false"
  if (first) printf ","
  first=1
  printf "{\"id\":\"%s\",\"name\":\"%s\",\"pkg\":\"%s\",\"installed\":%s}", id, nm, pk, ins
}
END { printf "]\n" }
