# Scenario

- Single node kubernetes cluster

- Dummy go application deployed into the cluster
 
- Host running Container Linux (CoreOS) 

- Selinux enforcing mode in the host

- Seccomp enabled at Docker runtime

- Istio running for egress functionality

- PodSecurityPolicies deployed to manage container security contexts 

- This scenario does not tend to be production-ready but a scenario where to do simple experiments.

# Provision VPC  

Terraform has been used to provision a VPC and the EC2 instance hosting the kube cluster. The following 
snippet specifies how to provisions the infrastructure via Terraform

````
export AWS_PROFILE=enekofb
cd $istio-poc/kubernetes
terraform init --upgrade
terraform apply
````

as a result 

```
public_ip = 18.202.130.41
ssh_user = core
```

- By using Terraform Workspaces is direct to get different environments based on the same [configuration](https://www.terraform.io/docs/state/workspaces.html)   

```
    terraform workspace create production 
    terraform workspace select staging
```

# Provision Kubernetes

0. Copy the scripts into the host via scp `scp scripts/* core@18.202.130.41:/home/core`

1. Provision Single-node cluster

- Execute the script `provision-single-node-kubernetes.sh` as root into the host `sudo bash -x provision-single-node-kubernetes.sh`

- Check provisioning has been done successfully 

```
core@ip-10-16-129-204 ~ $ sestatus
SELinux clstatus:                 enabled
SELinuxfs mount:                /sys/fs/selinux
SELinux root directory:         /etc/selinux
Loaded policy name:             mcs
Current mode:                   enforcing
Mode from config file:          enforcing
Policy MLS status:              enabled
Policy deny_unknown status:     allowed
Max kernel policy version:      31

core@ip-10-16-129-204 ~ $ kubectl get nodes
NAME                                          STATUS    ROLES     AGE       VERSION
ip-10-16-129-204.us-west-2.compute.internal   Ready     master    7m        v1.11.0

N.B: docker info has to show both seccomp and selinux enabled

```

2. Provision istio

- Execute the script `sudo bash -x deploy-istio.sh` to provision `helm` and `istio`

- Check provisioning has been done successfully 

```
core@ip-10-16-129-204 ~ $ helm ls
NAME 	REVISION	UPDATED                 	STATUS  	CHART      	NAMESPACE
istio	1       	Fri Oct  5 21:28:46 2018	DEPLOYED	istio-1.0.0	1.0.0      	istio-system
core@ip-10-16-129-204 ~ $ kubectl get pods -n istio-system

core@ip-10-43-243-73 ~ $ kubectl get pods -n istio-system -w
NAME                                        READY   STATUS    RESTARTS   AGE
istio-citadel-657777464f-59rtq              1/1     Running   0          25s
istio-egressgateway-6497dfdfc-96d25         1/1     Running   0          25s
istio-galley-5664cf4486-c9b8l               0/1     Running   0          25s
istio-ingressgateway-787bf4cb5b-6lgfr       1/1     Running   0          25s
istio-pilot-54b6f64977-zm42h                1/2     Running   0          25s
istio-policy-659559675c-fjqkt               2/2     Running   0          25s
istio-sidecar-injector-7ddfb55469-p2kts     0/1     Running   0          24s
istio-statsd-prom-bridge-67bbcc746c-pkbnf   1/1     Running   0          25s
istio-telemetry-7d4f794c8d-vqjbj            2/2     Running   0          25s
prometheus-6967c997cf-swkgw                 1/1     Running   0          25s
```

# Deploy the application (pegress)

The target application is a simple golang web server that listens in 8080 port and replies google.com page when requested 
the root path. 

```
func main() {
	http.HandleFunc("/", func (w http.ResponseWriter, r *http.Request) {

		resp, err := http.Get("http://www.google.com")
		if err != nil {
			panic(err)
		}
		defer resp.Body.Close()
		body, err := ioutil.ReadAll(resp.Body)
		fmt.Fprintf(w, string(body))
	})

	http.ListenAndServe(":8080", handlers.LoggingHandler(os.Stdout, http.DefaultServeMux))
}
```

The code lives in [pegress](./pegress).

In order to provision the application executes the script `deploy-pegress.sh` and check that provisioning has been done successfully 

```
core@ip-10-16-129-204 ~ $ kubectl get pods
NAME                                     READY     STATUS    RESTARTS   AGE
pegress-alpine-istio-56749cc498-9rdrx   2/2     Running   0          7m48s

core@ip-10-16-129-204 ~ $ istioctl get serviceentry
NAME         KIND                                        NAMESPACE
google-ext   ServiceEntry.networking.istio.io.v1alpha3   default

```

and check whether egress is working properly by curl pegress-* and having the same output

```
core@ip-10-43-243-73 ~ $ kubectl get svc
NAME                   TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
kubernetes             ClusterIP   10.96.0.1       <none>        443/TCP   13m
pegress-alpine-istio   LoadBalancer   10.109.120.254   a414308f7c8f111e8873a0220346b082-2022439982.eu-west-1.elb.amazonaws.com   80:32225/TCP   24m
``` 

check that the service is reachable internally via kubernetes svc cluster ip 

```
core@ip-10-16-129-204 ~ $ curl 10.109.120.254
```

check that the service is externally reachable via AWS ELB  

```
➜  kubernetes git:(master) ✗ curl http://a414308f7c8f111e8873a0220346b082-2022439982.eu-west-1.elb.amazonaws.com
```

# Scenario acceptance 

In addition to the provision scripts an acceptance testing script has been shipped to verify
the scenario setup. It could be executed by `bash -x acceptance.sh` . It tests that ...

1. Kubernetes scenario with limited permissions
2. Seccomp test
3. PodSecurityPolicies are enabled
4. Secure egress is setup via Istio

```
core@ip-10-43-243-73 ~ $ bash -x acceptance.sh

+ kubectl auth can-i get pods -n kube-system
+ grep no
no - no RBAC policy matched
+ echo 'Cannot access to kube-system'
Cannot access to kube-system
+ kubectl auth can-i get pods -n istio-system
+ grep no
no - no RBAC policy matched
+ echo 'Cannot access to istio-system'
Cannot access to istio-system
+ kubectl apply -f -
+ cat
pod/seccomp-test created
+ sleep 60
+ kubectl describe pods seccomp-test
+ grep kubernetes.io/psp=restricted-custom
+ echo 'PSP enabled'
PSP enabled
+ kubectl logs seccomp-test
+ grep 'Unable to dump key: Operation not permitted'
Unable to dump key: Operation not permitted
+ echo 'SECCOMP working'
SECCOMP working
+ kubectl delete pod seccomp-test
pod "seccomp-test" deleted
++ kubectl get pod -l app=pegress-alpine-istio -o 'jsonpath={.items[0].metadata.name}'
+ export POD=pegress-alpine-istio-56749cc498-9rdrx
+ POD=pegress-alpine-istio-56749cc498-9rdrx
+ kubectl exec -ti pegress-alpine-istio-56749cc498-9rdrx -- wget -O - www.google.com
+ grep Lucky
Defaulting container name to pegress.
Use 'kubectl describe pod/pegress-alpine-istio-56749cc498-9rdrx -n default' to see all of the containers in this pod.
})();</script><div id="mngb"> <div id=gbar><nobr><b class=gb1>Search</b> <a class=gb1 href="http://www.google.ie/imghp?hl=en&tab=wi">Images</a> <a class=gb1 href="http://maps.google.ie/maps?hl=en&tab=wl">Maps</a> <a class=gb1 href="https://play.google.com/?hl=en&tab=w8">Play</a> <a class=gb1 href="http://www.youtube.com/?gl=IE&tab=w1">YouTube</a> <a class=gb1 href="http://news.google.ie/nwshp?hl=en&tab=wn">News</a> <a class=gb1 href="https://mail.google.com/mail/?tab=wm">Gmail</a> <a class=gb1 href="https://drive.google.com/?tab=wo">Drive</a> <a class=gb1 style="text-decoration:none" href="https://www.google.ie/intl/en/options/"><u>More</u> &raquo;</a></nobr></div><div id=guser width=100%><nobr><span id=gbn class=gbi></span><span id=gbf class=gbf></span><span id=gbe></span><a href="http://www.google.ie/history/optout?hl=en" class=gb4>Web History</a> | <a  href="/preferences?hl=en" class=gb4>Settings</a> | <a target=_top id=gb_70 href="https://accounts.google.com/ServiceLogin?hl=en&passive=true&continue=http://www.google.com/" class=gb4>Sign in</a></nobr></div><div class=gbh style=left:0></div><div class=gbh style=right:0></div> </div><center><br clear="all" id="lgpd"><div id="lga"><img alt="Google" height="92" src="/images/branding/googlelogo/1x/googlelogo_white_background_color_272x92dp.png" style="padding:28px 0 14px" width="272" id="hplogo" onload="window.lol&&lol()"><br><br></div><form action="/search" name="f"><table cellpadding="0" cellspacing="0"><tr valign="top"><td width="25%">&nbsp;</td><td align="center" nowrap=""><input name="ie" value="ISO-8859-1" type="hidden"><input value="en-IE" name="hl" type="hidden"><input name="source" type="hidden" value="hp"><input name="biw" type="hidden"><input name="bih" type="hidden"><div class="ds" style="height:32px;margin:4px 0"><input style="color:#000;margin:0;padding:5px 8px 0 6px;vertical-align:top" autocomplete="off" class="lst" value="" title="Google Search" maxlength="2048" name="q" size="57"></div><br style="line-height:0"><span class="ds"><span class="lsbb"><input class="lsb" value="Google Search" name="btnG" type="submit"></span></span><span class="ds"><span class="lsbb"><input class="lsb" value="I'm Feeling Lucky" name="btnI" onclick="if(this.form.q.value)this.checked=1; else top.location='/doodles/'" type="submit"></span></span></td><td class="fl sblc" align="left" nowrap="" width="25%"><a href="/advanced_search?hl=en-IE&amp;authuser=0">Advanced search</a><a href="/language_tools?hl=en-IE&amp;authuser=0">Language tools</a></td></tr></table><input id="gbv" name="gbv" type="hidden" value="1"><script nonce="iUesrqCdhSuOJqStOZGlyA==">(function(){var a,b="1";if(document&&document.getElementById)if("undefined"!=typeof XMLHttpRequest)b="2";else if("undefined"!=typeof ActiveXObject){var c,d,e=["MSXML2.XMLHTTP.6.0","MSXML2.XMLHTTP.3.0","MSXML2.XMLHTTP","Microsoft.XMLHTTP"];for(c=0;d=e[c++];)try{new ActiveXObject(d),b="2"}catch(h){}}a=b;if("2"==a&&-1==location.search.indexOf("&gbv=2")){var f=google.gbvu,g=document.getElementById("gbv");g&&(g.value=a);f&&window.setTimeout(function(){location.href=f},0)};}).call(this);</script></form><div id="gac_scont"></div><div style="font-size:83%;min-height:3.5em"><br><div id="prm"><style>.szppmdbYutt__middle-slot-promo{font-size:small;margin-bottom:32px}.szppmdbYutt__middle-slot-promo a.ZIeIlb{display:inline-block;text-decoration:none}.szppmdbYutt__middle-slot-promo img{border:none;margin-right:5px;vertical-align:middle}</style><div class="szppmdbYutt__middle-slot-promo" data-ved="0ahUKEwiysbH4ofDdAhUHIcAKHdJ8BBoQnIcBCAQ"><span>To all the teachers whose job is never finished, </span><a class="NKcBbd" href="https://www.google.com/url?q=https://edu.google.com/intl/en_uk/worldteachersday%3Futm_source%3Dgoogle%26utm_medium%3Dhpp%26utm_campaign%3Dhpp-landingpage&amp;source=hpp&amp;id=19008712&amp;ct=3&amp;usg=AFQjCNFnEyXsN2jXgT0iq2FZKzS7ITd09Q&amp;sa=X&amp;ved=0ahUKEwiysbH4ofDdAhUHIcAKHdJ8BBoQ8IcBCAU" rel="nofollow">Happy World Teachers&#8217; Day</a></div></div><div id="gws-output-pages-elements-homepage_additional_languages__als"><style>#gws-output-pages-elements-homepage_additional_languages__als{font-size:small;margin-bottom:24px}#SIvCob{display:inline-block;line-height:28px;}#SIvCob a{padding:0 3px;}.H6sW5{display:inline-block;margin:0 2px;white-space:nowrap}.z4hgWe{display:inline-block;margin:0 2px}</style><div id="SIvCob">Google offered in:  <a href="http://www.google.com/setprefs?sig=0_ayHfLEt1CQ3ThtYKV9NTKwoPZBs%3D&amp;hl=ga&amp;source=homepage&amp;sa=X&amp;ved=0ahUKEwiysbH4ofDdAhUHIcAKHdJ8BBoQ2ZgBCAc">Gaeilge</a>  </div></div></div><span id="footer"><div style="font-size:10pt"><div style="margin:19px auto;text-align:center" id="fll"><a href="/intl/en/ads/">Advertising�Programs</a><a href="http://www.google.ie/intl/en/services/">Business Solutions</a><a href="/intl/en/about.html">About Google</a><a href="http://www.google.com/setprefdomain?prefdom=IE&amp;prev=http://www.google.ie/&amp;sig=K_fTRJ2NmZ4Q59Lwnro2UaUBPxbGk%3D">Google.ie</a></div></div><p style="color:#767676;font-size:8pt">&copy; 2018 - <a href="/intl/en/policies/privacy/">Privacy</a> - <a href="/intl/en/policies/terms/">Terms</a></p></span></center><script nonce="iUesrqCdhSuOJqStOZGlyA==">(function(){window.google.cdo={height:0,width:0};(function(){var a=window.innerWidth,b=window.innerHeight;if(!a||!b){var c=window.document,d="CSS1Compat"==c.compatMode?c.documentElement:c.body;a=d.clientWidth;b=d.clientHeight}a&&b&&(a!=google.cdo.width||b!=google.cdo.height)&&google.log("","","/client_204?&atyp=i&biw="+a+"&bih="+b+"&ei="+google.kEI);}).call(this);})();</script><div id="xjsd"></div><div id="xjsi"><script nonce="iUesrqCdhSuOJqStOZGlyA==">(function(){function c(b){window.setTimeout(function(){var a=document.createElement("script");a.src=b;google.timers&&google.timers.load.t&&google.tick&&google.tick("load",{gen204:"xjsls",clearcut:31});document.getElementById("xjsd").appendChild(a)},0)}google.dljp=function(b,a){google.xjsu=b;c(a)};google.dlj=c;}).call(this);if(!google.xjs){window._=window._||{};window._DumpException=window._._DumpException=function(e){throw e};window._F_installCss=window._._F_installCss=function(c){};google.dljp('/xjs/_/js/k\x3dxjs.hp.en.CoxWx86t6ak.O/m\x3dsb_he,d/am\x3dYsBs/rt\x3dj/d\x3d1/rs\x3dACT90oF2F-CS0BULhOLTBzCllxGtoWsIPA','/xjs/_/js/k\x3dxjs.hp.en.CoxWx86t6ak.O/m\x3dsb_he,d/am\x3dYsBs/rt\x3dj/d\x3d1/rs\x3dACT90oF2F-CS0BULhOLTBzCllxGtoWsIPA');google.xjs=1;}google.pmc={"sb_he":{"agen":true,"cgen":true,"client":"heirloom-hp","dh":true,"dhqt":true,"ds":"","ffql":"en","fl":true,"host":"google.com","isbh":28,"jsonp":true,"lm":true,"msgs":{"cibl":"Clear Search","dym":"Did you mean:","lcky":"I\u0026#39;m Feeling Lucky","lml":"Learn more","oskt":"Input tools","psrc":"This search was removed from your \u003Ca href=\"/history\"\u003EWeb History\u003C/a\u003E","psrl":"Remove","sbit":"Search by image","srch":"Google Search"},"ovr":{},"pq":"","refpd":true,"rfs":[],"sbpl":24,"sbpr":24,"scd":10,"sce":5,"stok":"GWUh5aDLoyKIqoJU-NLSgp6blqA","uhde":false},"d":{},"ZI/YVQ":{},"Qnk92g":{},"U5B21g":{},"DPBNMg":{},"YFCs/g":{}};google.x(null,function(){});(function(){var r=[];google.plm(r);})();(function(){var m=[]
+ '[' 0 -eq 0 ']'
+ echo 'Egreess worked'
Egreess worked
+ grep Lucky
+ kubectl exec -ti pegress-alpine-istio-56749cc498-9rdrx -- wget -O - http://34.222.7.95 --header 'Host: www.google.com'
Defaulting container name to pegress.
Use 'kubectl describe pod/pegress-alpine-istio-56749cc498-9rdrx -n default' to see all of the containers in this pod.
})();</script><div id="mngb"> <div id=gbar><nobr><b class=gb1>Search</b> <a class=gb1 href="http://www.google.ie/imghp?hl=en&tab=wi">Images</a> <a class=gb1 href="http://maps.google.ie/maps?hl=en&tab=wl">Maps</a> <a class=gb1 href="https://play.google.com/?hl=en&tab=w8">Play</a> <a class=gb1 href="http://www.youtube.com/?gl=IE&tab=w1">YouTube</a> <a class=gb1 href="http://news.google.ie/nwshp?hl=en&tab=wn">News</a> <a class=gb1 href="https://mail.google.com/mail/?tab=wm">Gmail</a> <a class=gb1 href="https://drive.google.com/?tab=wo">Drive</a> <a class=gb1 style="text-decoration:none" href="https://www.google.ie/intl/en/options/"><u>More</u> &raquo;</a></nobr></div><div id=guser width=100%><nobr><span id=gbn class=gbi></span><span id=gbf class=gbf></span><span id=gbe></span><a href="http://www.google.ie/history/optout?hl=en" class=gb4>Web History</a> | <a  href="/preferences?hl=en" class=gb4>Settings</a> | <a target=_top id=gb_70 href="https://accounts.google.com/ServiceLogin?hl=en&passive=true&continue=http://www.google.com/" class=gb4>Sign in</a></nobr></div><div class=gbh style=left:0></div><div class=gbh style=right:0></div> </div><center><br clear="all" id="lgpd"><div id="lga"><img alt="Google" height="92" src="/images/branding/googlelogo/1x/googlelogo_white_background_color_272x92dp.png" style="padding:28px 0 14px" width="272" id="hplogo" onload="window.lol&&lol()"><br><br></div><form action="/search" name="f"><table cellpadding="0" cellspacing="0"><tr valign="top"><td width="25%">&nbsp;</td><td align="center" nowrap=""><input name="ie" value="ISO-8859-1" type="hidden"><input value="en-IE" name="hl" type="hidden"><input name="source" type="hidden" value="hp"><input name="biw" type="hidden"><input name="bih" type="hidden"><div class="ds" style="height:32px;margin:4px 0"><input style="color:#000;margin:0;padding:5px 8px 0 6px;vertical-align:top" autocomplete="off" class="lst" value="" title="Google Search" maxlength="2048" name="q" size="57"></div><br style="line-height:0"><span class="ds"><span class="lsbb"><input class="lsb" value="Google Search" name="btnG" type="submit"></span></span><span class="ds"><span class="lsbb"><input class="lsb" value="I'm Feeling Lucky" name="btnI" onclick="if(this.form.q.value)this.checked=1; else top.location='/doodles/'" type="submit"></span></span></td><td class="fl sblc" align="left" nowrap="" width="25%"><a href="/advanced_search?hl=en-IE&amp;authuser=0">Advanced search</a><a href="/language_tools?hl=en-IE&amp;authuser=0">Language tools</a></td></tr></table><input id="gbv" name="gbv" type="hidden" value="1"><script nonce="GRlMi1ROYzTpEV4A9PBj6A==">(function(){var a,b="1";if(document&&document.getElementById)if("undefined"!=typeof XMLHttpRequest)b="2";else if("undefined"!=typeof ActiveXObject){var c,d,e=["MSXML2.XMLHTTP.6.0","MSXML2.XMLHTTP.3.0","MSXML2.XMLHTTP","Microsoft.XMLHTTP"];for(c=0;d=e[c++];)try{new ActiveXObject(d),b="2"}catch(h){}}a=b;if("2"==a&&-1==location.search.indexOf("&gbv=2")){var f=google.gbvu,g=document.getElementById("gbv");g&&(g.value=a);f&&window.setTimeout(function(){location.href=f},0)};}).call(this);</script></form><div id="gac_scont"></div><div style="font-size:83%;min-height:3.5em"><br><div id="prm"><style>.szppmdbYutt__middle-slot-promo{font-size:small;margin-bottom:32px}.szppmdbYutt__middle-slot-promo a.ZIeIlb{display:inline-block;text-decoration:none}.szppmdbYutt__middle-slot-promo img{border:none;margin-right:5px;vertical-align:middle}</style><div class="szppmdbYutt__middle-slot-promo" data-ved="0ahUKEwjS4cH4ofDdAhWBOsAKHQJZAhAQnIcBCAQ"><span>To all the teachers whose job is never finished, </span><a class="NKcBbd" href="https://www.google.com/url?q=https://edu.google.com/intl/en_uk/worldteachersday%3Futm_source%3Dgoogle%26utm_medium%3Dhpp%26utm_campaign%3Dhpp-landingpage&amp;source=hpp&amp;id=19008712&amp;ct=3&amp;usg=AFQjCNFnEyXsN2jXgT0iq2FZKzS7ITd09Q&amp;sa=X&amp;ved=0ahUKEwjS4cH4ofDdAhWBOsAKHQJZAhAQ8IcBCAU" rel="nofollow">Happy World Teachers&#8217; Day</a></div></div><div id="gws-output-pages-elements-homepage_additional_languages__als"><style>#gws-output-pages-elements-homepage_additional_languages__als{font-size:small;margin-bottom:24px}#SIvCob{display:inline-block;line-height:28px;}#SIvCob a{padding:0 3px;}.H6sW5{display:inline-block;margin:0 2px;white-space:nowrap}.z4hgWe{display:inline-block;margin:0 2px}</style><div id="SIvCob">Google offered in:  <a href="http://www.google.com/setprefs?sig=0_-Hg0CRm0gaT9je4rrLgQgADBhic%3D&amp;hl=ga&amp;source=homepage&amp;sa=X&amp;ved=0ahUKEwjS4cH4ofDdAhWBOsAKHQJZAhAQ2ZgBCAc">Gaeilge</a>  </div></div></div><span id="footer"><div style="font-size:10pt"><div style="margin:19px auto;text-align:center" id="fll"><a href="/intl/en/ads/">Advertising�Programs</a><a href="http://www.google.ie/intl/en/services/">Business Solutions</a><a href="/intl/en/about.html">About Google</a><a href="http://www.google.com/setprefdomain?prefdom=IE&amp;prev=http://www.google.ie/&amp;sig=K_LpSWGolVE2UV8svLb_a66-lss6A%3D">Google.ie</a></div></div><p style="color:#767676;font-size:8pt">&copy; 2018 - <a href="/intl/en/policies/privacy/">Privacy</a> - <a href="/intl/en/policies/terms/">Terms</a></p></span></center><script nonce="GRlMi1ROYzTpEV4A9PBj6A==">(function(){window.google.cdo={height:0,width:0};(function(){var a=window.innerWidth,b=window.innerHeight;if(!a||!b){var c=window.document,d="CSS1Compat"==c.compatMode?c.documentElement:c.body;a=d.clientWidth;b=d.clientHeight}a&&b&&(a!=google.cdo.width||b!=google.cdo.height)&&google.log("","","/client_204?&atyp=i&biw="+a+"&bih="+b+"&ei="+google.kEI);}).call(this);})();</script><div id="xjsd"></div><div id="xjsi"><script nonce="GRlMi1ROYzTpEV4A9PBj6A==">(function(){function c(b){window.setTimeout(function(){var a=document.createElement("script");a.src=b;google.timers&&google.timers.load.t&&google.tick&&google.tick("load",{gen204:"xjsls",clearcut:31});document.getElementById("xjsd").appendChild(a)},0)}google.dljp=function(b,a){google.xjsu=b;c(a)};google.dlj=c;}).call(this);if(!google.xjs){window._=window._||{};window._DumpException=window._._DumpException=function(e){throw e};window._F_installCss=window._._F_installCss=function(c){};google.dljp('/xjs/_/js/k\x3dxjs.hp.en.CoxWx86t6ak.O/m\x3dsb_he,d/am\x3dYsBs/rt\x3dj/d\x3d1/rs\x3dACT90oF2F-CS0BULhOLTBzCllxGtoWsIPA','/xjs/_/js/k\x3dxjs.hp.en.CoxWx86t6ak.O/m\x3dsb_he,d/am\x3dYsBs/rt\x3dj/d\x3d1/rs\x3dACT90oF2F-CS0BULhOLTBzCllxGtoWsIPA');google.xjs=1;}google.pmc={"sb_he":{"agen":true,"cgen":true,"client":"heirloom-hp","dh":true,"dhqt":true,"ds":"","ffql":"en","fl":true,"host":"google.com","isbh":28,"jsonp":true,"lm":true,"msgs":{"cibl":"Clear Search","dym":"Did you mean:","lcky":"I\u0026#39;m Feeling Lucky","lml":"Learn more","oskt":"Input tools","psrc":"This search was removed from your \u003Ca href=\"/history\"\u003EWeb History\u003C/a\u003E","psrl":"Remove","sbit":"Search by image","srch":"Google Search"},"ovr":{},"pq":"","refpd":true,"rfs":[],"sbpl":24,"sbpr":24,"scd":10,"sce":5,"stok":"_jYu3Ik87ZmsBoJq8rCdLv7ht-M","uhde":false},"d":{},"ZI/YVQ":{},"Qnk92g":{},"U5B21g":{},"DPBNMg":{},"YFCs/g":{}};google.x(null,function(){});(function(){var r=[];google.plm(r);})();(function(){var m=[]
+ '[' 0 -eq 0 ']'
+ echo 'Egreess not bypassed'
Egreess not bypassed
```

# Scenario hardened 

The previous scenario has been iterated to incorporate security features around the different levels
 of the stack.  If we take as reference the following [post](https://kubernetes.io/blog/2018/07/18/11-ways-not-to-get-hacked/) that defines
the following eleven topics.

Part One: The Control Plane

    1. TLS Everywhere
    2. Enable RBAC with Least Privilege, Disable ABAC, and Monitor Logs
    3. Use Third Party Auth for API Server
    4. Separate and Firewall your etcd Cluster
    5. Rotate Encryption Keys
    
Part Two: Workloads

    6. Use Linux Security Features and PodSecurityPolicies
    7. Statically Analyse YAML
    8. Run Containers as a Non-Root User
    9. Use Network Policies
    10. Scan Images and Run IDS

Part Three: The Future

    11. Run a Service Mesh
    
We could say that the scenario incorporated 2,6,8,9,11 as reported below

## 2: RBAC configuration

By setting up RBAC in the api server

```
     },
            "Image": "sha256:dcb029b5e3ad1b17b4671a2b2b56983cdba39ce40f35a1bdd6e3a5492df789d3",
            "Volumes": null,
            "WorkingDir": "",
            "Entrypoint": [
                "kube-apiserver",
                "--authorization-mode=Node,RBAC",
```

## 6: OS

Using CoreOS (Container Linux) that is an inmutable linux distro and enabling iptables on it

```
ip-10-16-129-167 core # cat /etc/os-release
NAME="Container Linux by CoreOS"
ID=coreos
VERSION=1855.4.0
VERSION_ID=1855.4.0
BUILD_ID=2018-09-11-0003
PRETTY_NAME="Container Linux by CoreOS 1855.4.0 (Rhyolite)"
ANSI_COLOR="38;5;75"
HOME_URL="https://coreos.com/"
BUG_REPORT_URL="https://issues.coreos.com"
COREOS_BOARD="amd64-usr"
```

- coreos and selinux https://github.com/coreos/bugs/issues/2421

```
ip-10-16-129-167 core # docker info
Containers: 97
 Running: 49
 Paused: 0
 Stopped: 48
Images: 23
Server Version: 18.06.1-ce
Storage Driver: overlay2
 Backing Filesystem: extfs
 Supports d_type: true
 Native Overlay Diff: true
Logging Driver: json-file
Cgroup Driver: cgroupfs
Plugins:
 Volume: local
 Network: bridge host macvlan null overlay
 Log: awslogs fluentd gcplogs gelf journald json-file logentries splunk syslog
Swarm: inactive
Runtimes: runc
Default Runtime: runc
Init Binary: docker-init
containerd version: 468a545b9edcd5932818eb9de8e72413e616e86e
runc version: 69663f0bd4b60df09991c08812a60108003fa340
init version: v0.13.2 (expected: fec3683b971d9c3ef73f284f176672c44b448662)

Security Options:
 seccomp
  Profile: default
 selinux

Kernel Version: 4.14.67-coreos
Operating System: Container Linux by CoreOS 1855.4.0 (Rhyolite)
OSType: linux
Architecture: x86_64
CPUs: 2
Total Memory: 3.853GiB
Name: ip-10-16-129-167.us-west-2.compute.internal
ID: CAUR:AQV6:VCFE:BBES:OD5T:KI6M:S4A6:PYGR:ABWS:PLDT:HIZV:MVLA
Docker Root Dir: /var/lib/docker
Debug Mode (client): false
Debug Mode (server): false
Registry: https://index.docker.io/v1/
Labels:
Experimental: false
Insecure Registries:
 127.0.0.0/8
Live Restore Enabled: false
```

## 6: Docker

By enabling Seccomp runtime profile 

```
ip-10-16-129-167 core # docker info
...

Security Options:
 seccomp
  Profile: default
 selinux
```


- CoreOS only uses seccomp `https://github.com/moby/moby/blob/master/profiles/seccomp/default.json`

- AppArmor not supported in CoreOS

## 6: Kubernetes

- Using pod security policies for both priviledged and non privileged workloads

```
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: restricted-custom
  annotations:
    seccomp.security.alpha.kubernetes.io/allowedProfileNames: 'docker/default'
    seccomp.security.alpha.kubernetes.io/defaultProfileName:  'docker/default'
spec:
  privileged: false
  # Required to prevent escalations to root.
  allowPrivilegeEscalation: false
  allowedCapabilities:
  - NET_ADMIN
  # Allow core volume types.
  volumes:
    - 'configMap'
    - 'emptyDir'
    - 'projected'
    - 'secret'
    - 'downwardAPI'
    # Assume that persistentVolumes set up by the cluster admin are safe to use.
    - 'persistentVolumeClaim'
  hostNetwork: false
  hostIPC: false
  hostPID: false
  runAsUser:
    # Require the container to run without root privileges.
    rule: 'RunAsAny' ##  TODO: REMOVE ME NOTE THAT THIS IS BEACAUSE OF ISTIO PROXY
  seLinux:
    # This policy assumes the nodes are using AppArmor rather than SELinux.
    rule: 'RunAsAny'
  supplementalGroups:
    rule: 'MustRunAs'
    ranges:
      # Forbid adding the root group.
      - min: 1
        max: 65535
  fsGroup:
    rule: 'MustRunAs'
    ranges:
      # Forbid adding the root group.
      - min: 1
        max: 65535
  readOnlyRootFilesystem: false
```

## 8: non root containers

- PodSecurityPolicy `single-node-cluster/scripts/deploy-pegress.sh`
- SecurityContext

```
        securityContext:
          privileged: false
          runAsNonRoot: true
          runAsUser: 1000

```

## 9: Network Policies

- Calico `kubectl apply -f https://docs.projectcalico.org/v3.1/getting-started/kubernetes/installation/hosted/kubeadm/1.7/calico.yaml`
   
## 11: Service Mesh

- Running istio 1.0.0 that proxies all application container 
    