from django.shortcuts import render,redirect
from django.http import HttpResponse,HttpRequest 
from .models import Vote,Votant,Departement,scoreDep,citation
from django.db.models import F
from .forms import vote_Form

def home(request):
	votes=Vote.objects.order_by('NumVote')
	Score=Vote.objects.order_by('-Score')
	cita=citation.objects.all()
	ip = getIP(request)
	deja_vote=False
	if Votant.objects.filter(ipvotant=ip).count() >0:
		deja_vote=True	
	dep=Departement.objects.order_by('id')
	return render(request,'vote/vote.html',{'votes':votes,'deja_vote':deja_vote,'dep':dep,'score':Score,'cita':cita})
	
def incrVote(request):
	if request.method =='POST':
		ip = getIP(request)
		if Votant.objects.filter(ipvotant=ip).count() ==0:
			form = vote_Form(request.POST)
			if form.is_valid():
				formVote=form.cleaned_data["formVote"]
				formDep=form.cleaned_data["formDep"]
				Vote.objects.filter(NumVote=formVote).update(Score=F('Score') + 1)
				scoreDep.objects.filter(VoteDep=formVote , NumDep=formDep).update(ScoreDep=F('ScoreDep')+1)
				voteur=Votant()
				voteur.ipvotant=ip
				voteur.save()
				return redirect('vote.views.home')
	else:
		form=vote_Form()
	return redirect('vote.views.home')

def getIP(request):
	ip=request.META.get('HTTP_X_FORWARDED_FOR')
	if ip:
		ip = ip.split(", ")[0]
	else:
		ip = request.META.get("REMOTE_ADDR", "")
	return ip
