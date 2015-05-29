from django.shortcuts import render
from django.http import HttpResponse,HttpRequest 
from .models import Vote,Votant,Departement,scoreDep
from django.db.models import F
from .forms import vote_Form

def home(request):
	votes=Vote.objects.order_by('NumVote')
	Score=Vote.objects.order_by('-Score')
	ip = getIP(request)
	str(ip)
	votant=Votant.objects.all
	dep=Departement.objects.all
	return render(request,'vote/vote.html',{'votes':votes,'ip':ip,'dep':dep,'score':Score,'votant':votant})
	
def incrVote(request):
	if request.method =='POST':
		form = vote_Form(request.POST)
		if form.is_valid():
			formVote=form.cleaned_data["formVote"]
			formDep=form.cleaned_data["formDep"]
			Vote.objects.filter(NumVote=formVote).update(Score=F('Score') + 1)
			scoreDep.objects.filter(VoteDep=formVote , NumDep=formDep).update(ScoreDep=F('ScoreDep')+1)
			voteur=Votant()
			voteur.IPVotant=getIP(request)
			voteur.save()
	else:
		form=vote_Form()
	return render(request,'vote/vote.html',locals())

def getIP(request):
	ip=request.META.get('HTTP_X_FORWARDED_FOR')
	if ip:
		ip = ip.split(", ")[0]
	else:
		ip = request.META.get("REMOTE_ADDR", "")
	return ip
