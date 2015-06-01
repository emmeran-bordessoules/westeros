from django.shortcuts import render
from vote.models import scoreDep
from vote.views import hasard

def home(request):
	score=scoreDep.objects.order_by('NumDep','-ScoreDep')[:800:8] # tri par département puis par score descendant puis prend un vote sur 8 dans les 800 premiers
	cita=hasard()
	return render(request,'carto/carto.html',{'score':score,'cita':cita})
