# create starpack expfep-linux-x86_64
# required:
#   sdx , tclkit , tclkit-cli

# linux x86-64 starpack
expfep-linux-x86_64: expfep.vfs/main.tcl
	sdx wrap expfep -runtime `which tclkit-cli`
	mv expfep expfep-linux-x86_64
