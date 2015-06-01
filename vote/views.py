from django.shortcuts import render,redirect
from django.http import HttpResponse,HttpRequest 
from .models import Vote,Votant,Departement,scoreDep,citation
from django.db.models import F
from .forms import vote_Form

def accueil(request):
	return render(request,'vote/accueil.html',locals())

def home(request):
	votes=Vote.objects.order_by('NumVote') # récupération des votes 
	Score=Vote.objects.order_by('-Score')  # récupération des votes triés en fonction de leur score
	cita=hasard()
	ip = getIP(request)
	deja_vote=False
	if Votant.objects.filter(ipvotant=ip).count() >0: # test si l'IP est dans la base de donnée
		deja_vote=True	
	dep=Departement.objects.order_by('id') # récupération des département
	return render(request,'vote/vote.html',{'votes':votes,'deja_vote':deja_vote,'dep':dep,'score':Score,'cita':cita})
	
def incrVote(request):
	if request.method =='POST':
		ip = getIP(request) 
		if Votant.objects.filter(ipvotant=ip).count() ==0: # test si l'IP est dans la base de donnée
			form = vote_Form(request.POST)
			if form.is_valid():
				formVote=form.cleaned_data["formVote"] # nettoyage des données
				formDep=form.cleaned_data["formDep"]   # nettoyage des données
				Vote.objects.filter(NumVote=formVote).update(Score=F('Score') + 1) # incrémentation du vote
				scoreDep.objects.filter(VoteDep=formVote , NumDep=formDep).update(ScoreDep=F('ScoreDep')+1) # incrémentation du vote en fonction du département
				voteur=Votant()
				voteur.ipvotant=ip # enregistrement de l'adresse IP
				voteur.save()      #
				return redirect('vote.views.home')
	else:
		form=vote_Form()
	return redirect('vote.views.home')

def getIP(request): # récupère l'IP client
	ip=request.META.get('HTTP_X_FORWARDED_FOR')
	if ip:
		ip = ip.split(", ")[0]
	else:
		ip = request.META.get("REMOTE_ADDR", "")
	return ip

def hasard(): # génération de citation
	return citation.objects.order_by('?')[0]